/**
 * @file dmod_stubs.c
 * @brief What dmlog.c takes from dmod and the selector does not have: nothing runs beside it, there are no files and no heap
 */
#include "dmod.h"

void  Dmod_Assert( int Condition, const char* Message, const char* File, int Line, const char* Function )
{
    (void)Message; (void)File; (void)Line; (void)Function;
    while( !Condition ) {}
}
bool  Dmod_CheckLogLevel( Dmod_LogLevel_t LogLevel ) { (void)LogLevel; return false; }
void  Dmod_EnterCritical( void ) {}
void  Dmod_ExitCritical( void ) {}
int   Dmod_FPrintf( void* File, const char* Format, ... ) { (void)File; (void)Format; return 0; }
void  Dmod_FileClose( void* File ) { (void)File; }
void* Dmod_FileOpen( const char* Path, const char* Mode ) { (void)Path; (void)Mode; return 0; }
size_t Dmod_FileRead( void* Buffer, size_t Size, size_t Count, void* File ) { (void)Buffer; (void)Size; (void)Count; (void)File; return 0; }
Dmod_FileSize_t Dmod_FileSize( void* File ) { (void)File; return 0; }
size_t Dmod_FileWrite( const void* Buffer, size_t Size, size_t Count, void* File ) { (void)Buffer; (void)Size; (void)Count; (void)File; return 0; }
void  Dmod_FreeEx( void* Ptr, bool Concatenate ) { (void)Ptr; (void)Concatenate; }
void* Dmod_GetStreamLogFile( Dmod_LogLevel_t LogLevel ) { (void)LogLevel; return 0; }
int   Dmod_Ioctl( void* File, int Command, void* Arg ) { (void)File; (void)Command; (void)Arg; return -1; }
void* Dmod_LockStdio( void* StdHandle ) { (void)StdHandle; return 0; }
void* Dmod_MallocEx( size_t Size, const char* ModuleName ) { (void)Size; (void)ModuleName; return 0; }
void  Dmod_ThreadSleep( uint32_t Milliseconds ) { (void)Milliseconds; }
void  Dmod_UnlockStdio( void* StdHandle ) { (void)StdHandle; }
const char* strerror( int errnum ) { (void)errnum; return ""; }
