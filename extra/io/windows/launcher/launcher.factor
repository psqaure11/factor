! Copyright (C) 2007, 2008 Doug Coleman, Slava Pestov.
! See http://factorcode.org/license.txt for BSD license.
USING: alien alien.c-types arrays continuations destructors io
io.windows libc io.nonblocking io.streams.duplex windows.types
math windows.kernel32 windows namespaces io.launcher kernel
sequences windows.errors assocs splitting system threads init ;
IN: io.windows.launcher

TUPLE: CreateProcess-args
       lpApplicationName
       lpCommandLine
       lpProcessAttributes
       lpThreadAttributes
       bInheritHandles
       dwCreateFlags
       lpEnvironment
       lpCurrentDirectory
       lpStartupInfo
       lpProcessInformation
       stdout-pipe stdin-pipe ;

: default-CreateProcess-args ( -- obj )
    0
    0
    "STARTUPINFO" <c-object>
    "STARTUPINFO" heap-size over set-STARTUPINFO-cb
    "PROCESS_INFORMATION" <c-object>
    {
        set-CreateProcess-args-bInheritHandles
        set-CreateProcess-args-dwCreateFlags
        set-CreateProcess-args-lpStartupInfo
        set-CreateProcess-args-lpProcessInformation
    } \ CreateProcess-args construct ;

: call-CreateProcess ( CreateProcess-args -- )
    {
        CreateProcess-args-lpApplicationName
        CreateProcess-args-lpCommandLine
        CreateProcess-args-lpProcessAttributes
        CreateProcess-args-lpThreadAttributes
        CreateProcess-args-bInheritHandles
        CreateProcess-args-dwCreateFlags
        CreateProcess-args-lpEnvironment
        CreateProcess-args-lpCurrentDirectory
        CreateProcess-args-lpStartupInfo
        CreateProcess-args-lpProcessInformation
    } get-slots CreateProcess win32-error=0/f ;

: escape-argument ( str -- newstr )
    [ [ dup CHAR: " = [ CHAR: \\ , ] when , ] each ] "" make ;

: join-arguments ( args -- cmd-line )
    [ "\"" swap escape-argument "\"" 3append ] map " " join ;

: app-name/cmd-line ( -- app-name cmd-line )
    +command+ get [
        " " split1
    ] [
        +arguments+ get unclip swap join-arguments
    ] if* ;

: cmd-line ( -- cmd-line )
    +command+ get [ +arguments+ get join-arguments ] unless* ;

: fill-lpApplicationName
    app-name/cmd-line
    pick set-CreateProcess-args-lpCommandLine
    over set-CreateProcess-args-lpApplicationName ;

: fill-lpCommandLine
    cmd-line over set-CreateProcess-args-lpCommandLine ;

: fill-dwCreateFlags
    0
    pass-environment? [ CREATE_UNICODE_ENVIRONMENT bitor ] when
    +detached+ get winnt? and [ DETACHED_PROCESS bitor ] when
    over set-CreateProcess-args-dwCreateFlags ;

: fill-lpEnvironment
    pass-environment? [
        [
            get-environment
            [ "=" swap 3append string>u16-alien % ] assoc-each
            "\0" %
        ] { } make >c-ushort-array
        over set-CreateProcess-args-lpEnvironment
    ] when ;

: make-CreateProcess-args ( -- args )
    default-CreateProcess-args
    wince? [ fill-lpApplicationName ] [ fill-lpCommandLine ] if
    fill-dwCreateFlags
    fill-lpEnvironment ;

M: windows-io run-process* ( desc -- handle )
    [
        make-CreateProcess-args
        dup call-CreateProcess
        CreateProcess-args-lpProcessInformation <process>
    ] with-descriptor ;

: dispose-process ( process-information -- )
    #! From MSDN: "Handles in PROCESS_INFORMATION must be closed
    #! with CloseHandle when they are no longer needed."
    dup PROCESS_INFORMATION-hProcess [ CloseHandle drop ] when*
    PROCESS_INFORMATION-hThread [ CloseHandle drop ] when* ;

: exit-code ( process -- n )
    PROCESS_INFORMATION-hProcess
    0 <ulong> [ GetExitCodeProcess ] keep *ulong
    swap win32-error=0/f ;

: process-exited ( process -- )
    dup process-handle exit-code
    over process-handle dispose-process
    swap notify-exit ;

: wait-for-processes ( processes -- ? )
    keys dup
    [ process-handle PROCESS_INFORMATION-hProcess ] map
    dup length swap >c-void*-array 0 0
    WaitForMultipleObjects
    dup HEX: ffffffff = [ win32-error ] when
    dup WAIT_TIMEOUT = [ 2drop t ] [ swap nth process-exited f ] if ;

: wait-loop ( -- )
    processes get dup assoc-empty?
    [ drop t ] [ wait-for-processes ] if
    [ 250 sleep ] when
    wait-loop ;

: start-wait-thread ( -- )
    [ wait-loop ] in-thread ;

[ start-wait-thread ] "io.windows.launcher" add-init-hook
