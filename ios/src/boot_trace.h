// Fight Night Champion iOS - startup trace & breadcrumbs (boot_trace.h)

#pragma once

#include <string>
#include <cstdint>

namespace fnc::boot {

void Open(const std::string& path);
void SetLogFilePath(const std::string& path);
void Trace(const std::string& line);
void SetEnabled(bool enabled);
void SetupAltStack();
void SetLastPPCBreadcrumb(uint32_t fn_addr, uint32_t lr, uint32_t r3);
size_t FormatLastPPCBreadcrumbs(char* buf, size_t buf_size);

}  // namespace fnc::boot

namespace nfsmw::boot {
using namespace fnc::boot;
}
