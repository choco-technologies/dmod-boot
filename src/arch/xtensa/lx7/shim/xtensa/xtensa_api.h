/* ESP-IDF >= 5.2: <xtensa/xtensa_api.h> is deprecated (the header moved to the include directory of the component xtensa and the
   old name only warns); the original header is used when there is no new one. */
#pragma once
#if __has_include(<xtensa_api.h>)
    #include <xtensa_api.h>
#else
    #include_next <xtensa/xtensa_api.h>
#endif
