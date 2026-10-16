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

#pragma once

#include <atomic>
#include <cstdint>

#ifdef CRASH_HANDLER
void installCrashHandler();
#endif

// OurTibia (16.10.2026): a small ring of the last server packets (opcode + time) and
// "breadcrumbs" from the client, written into crashreport.log when the client crashes.
namespace CrashTrail
{
    struct Entry { int64_t ms; int32_t kind; int32_t value; };
    inline constexpr uint32_t Size = 128;
    inline Entry entries[Size] {};
    inline std::atomic<uint32_t> next { 0 };
    inline void push(int32_t kind, int32_t value, int64_t ms)
    {
        const uint32_t i = next.fetch_add(1, std::memory_order_relaxed) % Size;
        entries[i] = Entry { ms, kind, value };
    }
}
