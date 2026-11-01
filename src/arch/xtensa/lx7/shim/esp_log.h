/* The log of ESP-IDF, for the FreeRTOS port: nothing is logged (the project has its own log); the arguments are not evaluated */
#ifndef ESP_LOG_H
#define ESP_LOG_H
#define ESP_LOGE( tag, format, ... )        do { (void)(tag); } while( 0 )
#define ESP_LOGW( tag, format, ... )        do { (void)(tag); } while( 0 )
#define ESP_LOGI( tag, format, ... )        do { (void)(tag); } while( 0 )
#define ESP_LOGD( tag, format, ... )        do { (void)(tag); } while( 0 )
#define ESP_LOGV( tag, format, ... )        do { (void)(tag); } while( 0 )
#define ESP_EARLY_LOGE( tag, format, ... )  ESP_LOGE( tag, format )
#define ESP_EARLY_LOGW( tag, format, ... )  ESP_LOGW( tag, format )
#define ESP_EARLY_LOGI( tag, format, ... )  ESP_LOGI( tag, format )
#define ESP_EARLY_LOGD( tag, format, ... )  ESP_LOGD( tag, format )
#define ESP_EARLY_LOGV( tag, format, ... )  ESP_LOGV( tag, format )
#endif
