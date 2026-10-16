/*
 * Copyright (c) 2010-2026 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */


// OurTibia (16.10.2026): crash reports for the Windows client (MSVC and MinGW builds).
// On a crash the client writes, next to the log, in its working directory:
//   crashreport.log - exception, registers, the call stack as module+offset
//                     (resolve offline with the MyOTS.map from the build), and the
//                     last 128 server packets received;
//   crash.dmp       - a minidump (stacks of all threads) for a debugger.
// dbghelp.dll is loaded at run time, nothing extra has to be linked.

#if defined(WIN32) && defined(CRASH_HANDLER)

#include <windows.h>
#include <imagehlp.h> // not dbghelp.h: the MSVC unity build mixes it with another imagehlp.h user

#include <atomic>
#include <cstdio>
#include <ctime>
#include <exception>
#include <csignal>

#include "crashhandler.h"

namespace
{
    using MiniDumpWriteDumpFn = BOOL(WINAPI*)(HANDLE, DWORD, HANDLE, MINIDUMP_TYPE, PMINIDUMP_EXCEPTION_INFORMATION, PMINIDUMP_USER_STREAM_INFORMATION, PMINIDUMP_CALLBACK_INFORMATION);
    using StackWalk64Fn = BOOL(WINAPI*)(DWORD, HANDLE, HANDLE, LPSTACKFRAME64, PVOID, PREAD_PROCESS_MEMORY_ROUTINE64, PFUNCTION_TABLE_ACCESS_ROUTINE64, PGET_MODULE_BASE_ROUTINE64, PTRANSLATE_ADDRESS_ROUTINE64);
    using SymInitializeFn = BOOL(WINAPI*)(HANDLE, PCSTR, BOOL);

    std::atomic<bool> g_inHandler { false };

    const char* exceptionName(DWORD code)
    {
        switch (code) {
            case EXCEPTION_ACCESS_VIOLATION: return "Access violation";
            case EXCEPTION_ARRAY_BOUNDS_EXCEEDED: return "Array bounds exceeded";
            case EXCEPTION_DATATYPE_MISALIGNMENT: return "Datatype misalignment";
            case EXCEPTION_FLT_DIVIDE_BY_ZERO: return "Float divide by zero";
            case EXCEPTION_ILLEGAL_INSTRUCTION: return "Illegal instruction";
            case EXCEPTION_INT_DIVIDE_BY_ZERO: return "Integer divide by zero";
            case EXCEPTION_STACK_OVERFLOW: return "Stack overflow";
            case EXCEPTION_IN_PAGE_ERROR: return "In page error";
            case EXCEPTION_PRIV_INSTRUCTION: return "Privileged instruction";
            case 0xC0000409: return "Stack buffer overrun / fast fail";
            case 0xC0000374: return "Heap corruption";
            case 0xE06D7363: return "C++ exception";
            default: return "Unknown exception";
        }
    }

    void moduleOf(DWORD64 addr, char* name, size_t nameSize, DWORD64& base)
    {
        HMODULE mod = nullptr;
        base = 0;
        name[0] = '\0';
        if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                               reinterpret_cast<LPCSTR>(addr), &mod) && mod) {
            base = reinterpret_cast<DWORD64>(mod);
            char full[MAX_PATH] = {};
            GetModuleFileNameA(mod, full, MAX_PATH);
            const char* slash = strrchr(full, '\\');
            snprintf(name, nameSize, "%s", slash ? slash + 1 : full);
        } else {
            snprintf(name, nameSize, "?");
        }
    }

    void writeTrail(FILE* f)
    {
        const uint32_t end = CrashTrail::next.load();
        const uint32_t count = end < CrashTrail::Size ? end : CrashTrail::Size;
        fprintf(f, "last %u server packets (oldest first, ms since start of the clock):\n", count);
        for (uint32_t k = 0; k < count; ++k) {
            const auto& e = CrashTrail::entries[(end - count + k) % CrashTrail::Size];
            fprintf(f, "  %lld  op 0x%02X (%d)\n", static_cast<long long>(e.ms), e.value & 0xFF, e.value);
        }
    }

    void writeReport(EXCEPTION_POINTERS* e, const char* reason)
    {
        char dir[MAX_PATH] = {};
        DWORD len = GetCurrentDirectoryA(MAX_PATH, dir);
        if (len == 0 || len >= MAX_PATH) snprintf(dir, sizeof(dir), ".");

        char logPath[MAX_PATH + 32];
        snprintf(logPath, sizeof(logPath), "%s\\crashreport.log", dir);
        FILE* f = fopen(logPath, "a");

        HMODULE dbghelp = LoadLibraryA("dbghelp.dll");
        auto symInit = dbghelp ? reinterpret_cast<SymInitializeFn>(GetProcAddress(dbghelp, "SymInitialize")) : nullptr;
        auto walk = dbghelp ? reinterpret_cast<StackWalk64Fn>(GetProcAddress(dbghelp, "StackWalk64")) : nullptr;
        auto tableAccess = dbghelp ? reinterpret_cast<PFUNCTION_TABLE_ACCESS_ROUTINE64>(GetProcAddress(dbghelp, "SymFunctionTableAccess64")) : nullptr;
        auto moduleBase = dbghelp ? reinterpret_cast<PGET_MODULE_BASE_ROUTINE64>(GetProcAddress(dbghelp, "SymGetModuleBase64")) : nullptr;
        auto dump = dbghelp ? reinterpret_cast<MiniDumpWriteDumpFn>(GetProcAddress(dbghelp, "MiniDumpWriteDump")) : nullptr;

        if (f) {
            time_t now = time(nullptr);
            char when[64];
            strftime(when, sizeof(when), "%Y-%m-%d %H:%M:%S", localtime(&now));
            fprintf(f, "== OurTibia client crashed (%s)\ncrash date: %s\n", reason, when);
            HMODULE exe = GetModuleHandleA(nullptr);
            fprintf(f, "exe base: 0x%016llX\n", static_cast<unsigned long long>(reinterpret_cast<DWORD64>(exe)));
        }

        if (e && e->ExceptionRecord && e->ContextRecord) {
            const auto* rec = e->ExceptionRecord;
            char mod[MAX_PATH];
            DWORD64 base;
            moduleOf(reinterpret_cast<DWORD64>(rec->ExceptionAddress), mod, sizeof(mod), base);
            if (f) {
                fprintf(f, "exception: %s (0x%08lX) at %s+0x%llX\n", exceptionName(rec->ExceptionCode), rec->ExceptionCode, mod,
                        static_cast<unsigned long long>(reinterpret_cast<DWORD64>(rec->ExceptionAddress) - base));
                if (rec->ExceptionCode == EXCEPTION_ACCESS_VIOLATION && rec->NumberParameters >= 2)
                    fprintf(f, "  %s address 0x%016llX\n", rec->ExceptionInformation[0] == 0 ? "read of" : (rec->ExceptionInformation[0] == 1 ? "write to" : "execute at"),
                            static_cast<unsigned long long>(rec->ExceptionInformation[1]));
#ifdef _WIN64
                const auto* c = e->ContextRecord;
                fprintf(f, "registers: rip=%016llX rsp=%016llX rbp=%016llX rax=%016llX rbx=%016llX rcx=%016llX rdx=%016llX\n",
                        c->Rip, c->Rsp, c->Rbp, c->Rax, c->Rbx, c->Rcx, c->Rdx);
#endif
            }

            if (f && symInit && walk && tableAccess && moduleBase) {
                HANDLE process = GetCurrentProcess();
                HANDLE thread = GetCurrentThread();
                symInit(process, nullptr, TRUE);
                CONTEXT ctx = *e->ContextRecord;
                STACKFRAME64 sf {};
                DWORD machine;
#ifdef _WIN64
                machine = IMAGE_FILE_MACHINE_AMD64;
                sf.AddrPC.Offset = ctx.Rip; sf.AddrStack.Offset = ctx.Rsp; sf.AddrFrame.Offset = ctx.Rbp;
#else
                machine = IMAGE_FILE_MACHINE_I386;
                sf.AddrPC.Offset = ctx.Eip; sf.AddrStack.Offset = ctx.Esp; sf.AddrFrame.Offset = ctx.Ebp;
#endif
                sf.AddrPC.Mode = sf.AddrStack.Mode = sf.AddrFrame.Mode = AddrModeFlat;
                fprintf(f, "call stack (module+offset):\n");
                for (int i = 0; i < 64; ++i) {
                    if (!walk(machine, process, thread, &sf, &ctx, nullptr, tableAccess, moduleBase, nullptr) || sf.AddrPC.Offset == 0)
                        break;
                    char m[MAX_PATH];
                    DWORD64 b;
                    moduleOf(sf.AddrPC.Offset, m, sizeof(m), b);
                    fprintf(f, "  #%02d %s+0x%llX\n", i, m, static_cast<unsigned long long>(sf.AddrPC.Offset - b));
                }
            }
        }

        if (f) {
            writeTrail(f);
            fprintf(f, "\n");
            fclose(f);
        }

        if (dump) {
            char dmpPath[MAX_PATH + 32];
            snprintf(dmpPath, sizeof(dmpPath), "%s\\crash.dmp", dir);
            HANDLE file = CreateFileA(dmpPath, GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
            if (file != INVALID_HANDLE_VALUE) {
                MINIDUMP_EXCEPTION_INFORMATION info {};
                info.ThreadId = GetCurrentThreadId();
                info.ExceptionPointers = e;
                info.ClientPointers = FALSE;
                dump(GetCurrentProcess(), GetCurrentProcessId(), file,
                     static_cast<MINIDUMP_TYPE>(MiniDumpWithThreadInfo | MiniDumpWithIndirectlyReferencedMemory | MiniDumpScanMemory),
                     e ? &info : nullptr, nullptr, nullptr);
                CloseHandle(file);
            }
        }

        char msg[MAX_PATH + 200];
        snprintf(msg, sizeof(msg), "OurTibia has crashed.\n\nA crash report was saved to:\n%s\n\nPlease send this file (and crash.dmp) to the team.", logPath);
        MessageBoxA(nullptr, msg, "OurTibia crashed", MB_OK | MB_ICONERROR);
    }

    LONG WINAPI unhandledFilter(EXCEPTION_POINTERS* e)
    {
        if (!g_inHandler.exchange(true))
            writeReport(e, "unhandled exception");
        return EXCEPTION_EXECUTE_HANDLER;
    }

    LONG WINAPI vectoredHandler(EXCEPTION_POINTERS* e)
    {
        // fatal errors that skip the unhandled filter (heap corruption, fast fail)
        const DWORD code = e->ExceptionRecord->ExceptionCode;
        if ((code == 0xC0000374 || code == 0xC0000409) && !g_inHandler.exchange(true)) {
            writeReport(e, "fatal error");
            TerminateProcess(GetCurrentProcess(), code);
        }
        return EXCEPTION_CONTINUE_SEARCH;
    }

    void terminateHandler()
    {
        if (!g_inHandler.exchange(true)) {
            const char* what = "unknown";
            try {
                if (auto ex = std::current_exception()) std::rethrow_exception(ex);
            } catch (const std::exception& ex) {
                what = ex.what();
            } catch (...) {
            }
            char reason[512];
            snprintf(reason, sizeof(reason), "std::terminate: %s", what);
            // capture the current context so the stack is written too
            CONTEXT ctx {};
            RtlCaptureContext(&ctx);
            EXCEPTION_RECORD rec {};
            rec.ExceptionCode = 0xE06D7363;
#ifdef _WIN64
            rec.ExceptionAddress = reinterpret_cast<PVOID>(ctx.Rip);
#else
            rec.ExceptionAddress = reinterpret_cast<PVOID>(ctx.Eip);
#endif
            EXCEPTION_POINTERS ptrs { &rec, &ctx };
            writeReport(&ptrs, reason);
        }
        TerminateProcess(GetCurrentProcess(), 3);
    }

    void abortHandler(int)
    {
        if (!g_inHandler.exchange(true)) {
            CONTEXT ctx {};
            RtlCaptureContext(&ctx);
            EXCEPTION_RECORD rec {};
            rec.ExceptionCode = 0x40000015; // STATUS_FATAL_APP_EXIT
#ifdef _WIN64
            rec.ExceptionAddress = reinterpret_cast<PVOID>(ctx.Rip);
#else
            rec.ExceptionAddress = reinterpret_cast<PVOID>(ctx.Eip);
#endif
            EXCEPTION_POINTERS ptrs { &rec, &ctx };
            writeReport(&ptrs, "abort()");
        }
        TerminateProcess(GetCurrentProcess(), 3);
    }
}

void installCrashHandler()
{
    SetUnhandledExceptionFilter(unhandledFilter);
    AddVectoredExceptionHandler(1, vectoredHandler);
    std::set_terminate(terminateHandler);
    signal(SIGABRT, abortHandler);
}

#endif
