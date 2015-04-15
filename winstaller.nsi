# Modern UI
!include MUI2.nsh

# define name of installer
name "Mullvad"
outFile "mullvad-v.exe"
 
# define installation directory
installDir "$PROGRAMFILES\Mullvad"

# TAP driver name
!define TAP "TAP0901"
 
!define MUI_FINISHPAGE_NOAUTOCLOSE

!insertmacro MUI_PAGE_WELCOME

!insertmacro MUI_PAGE_INSTFILES

!define MUI_FINISHPAGE_RUN "$INSTDIR\mullvad.exe"
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "Swedish"

;====================================================
; StrStr - Finds a given string in another given string.
;               Returns -1 if not found and the pos if found.
;          Input: head of the stack - string to find
;                      second in the stack - string to find in
;          Output: head of the stack
;====================================================
!macro StrStr un
Function ${un}StrStr
  Push $0
  Exch
  Pop $0 ; $0 now have the string to find
  Push $1
  Exch 2
  Pop $1 ; $1 now have the string to find in
  Exch
  Push $2
  Push $3
  Push $4
  Push $5

  StrCpy $2 -1
  StrLen $3 $0
  StrLen $4 $1
  IntOp $4 $4 - $3

  StrStr_loop:
    IntOp $2 $2 + 1
    IntCmp $2 $4 0 0 StrStrReturn_notFound
    StrCpy $5 $1 $3 $2
    StrCmp $5 $0 StrStr_done StrStr_loop

  StrStrReturn_notFound:
    StrCpy $2 -1

  StrStr_done:
    Pop $5
    Pop $4
    Pop $3
    Exch $2
    Exch 2
    Pop $0
    Pop $1
FunctionEnd
!macroend
!insertmacro StrStr ""
;!insertmacro StrStr "un."

     # start default section
section
    # Add/Remove Programs from the Control Panel
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Product" "DisplayName" "Mullvad"
    WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Product" "UninstallString" '"$INSTDIR\uninstall.exe"'
    WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Product" "NoModify" 1
    WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Product" "NoRepair" 1

    # set the installation directory as the destination for the following actions
    setOutPath $INSTDIR
    file /r /x openvpn dist\*

    ; Check if we are running on a 64 bit system.
    System::Call "kernel32::GetCurrentProcess() i .s"
    System::Call "kernel32::IsWow64Process(i s, *i .r0)"
    IntCmp $0 0 sys-32bit
  ;sys-64bit:
    setOutPath $INSTDIR\openvpn\bin
    file dist\openvpn\bin\amd64\*
    setOutPath $INSTDIR\openvpn\driver
    file dist\openvpn\driver\amd64\*
    setOutPath $INSTDIR    
    goto sysend
  sys-32bit:
    setOutPath $INSTDIR\openvpn\bin
    file dist\openvpn\bin\i686\*
    setOutPath $INSTDIR\openvpn\driver
    file dist\openvpn\driver\i686\*
    setOutPath $INSTDIR    
  sysend:

    # create the uninstaller
    writeUninstaller "$INSTDIR\uninstall.exe"
 
    # create a shortcut in the start menu programs directory
    # point the new shortcut at the program uninstaller
    createShortCut "$SMPROGRAMS\Mullvad.lnk" "$INSTDIR\mullvad.exe"

    # ICMPv4 rule to allow incoming time exceeded messages
    nsExec::ExecToLog 'netsh advfirewall firewall delete rule name="MullvadICMP11"'
    nsExec::ExecToLog 'netsh advfirewall firewall add rule name="MullvadICMP11" protocol=icmpv4:11,any dir=in action=allow'

    # Allow sending to the openvpn servers
    nsExec::ExecToLog 'netsh advfirewall firewall delete rule name="MullvadOpenVPN"'
    nsExec::ExecToLog 'netsh advfirewall firewall add rule name="MullvadOpenVPN" protocol=udp dir=out remoteport=1194-1215 action=allow'

    # Allow connecting to master
    nsExec::ExecToLog 'netsh advfirewall firewall delete rule name="MullvadMaster"'
    nsExec::ExecToLog 'netsh advfirewall firewall add rule name="MullvadMaster" protocol=tcp dir=out remoteport=51678 action=allow'

sectionEnd

;--------------------
;Post-install section

Section -post
  ;
  ; install/upgrade TAP driver if selected, using tapinstall.exe
  ;
    ; Should we install or update?
    ; If tapinstall error occurred, $5 will
    ; be nonzero.
    IntOp $5 0 & 0
    nsExec::ExecToStack '"$INSTDIR\openvpn\driver\tapinstall.exe" hwids ${TAP}'
    Pop $R0 # return value/error/timeout
    IntOp $5 $5 | $R0
    DetailPrint "tapinstall hwids returned: $R0"

    ; If tapinstall output string contains "${TAP}" we assume
    ; that TAP device has been previously installed,
    ; therefore we will update, not install.
    Push "${TAP}"
    Call StrStr
    Pop $R0

    IntCmp $5 0 "" tapinstall_check_error tapinstall_check_error
    IntCmp $R0 -1 tapinstall

 ;tapupdate:
    DetailPrint "TAP UPDATE"
    nsExec::ExecToLog '"$INSTDIR\openvpn\driver\tapinstall.exe" update "$INSTDIR\openvpn\driver\OemWin2k.inf" ${TAP}'
    Pop $R0 # return value/error/timeout
    ;Call CheckReboot
    IntOp $5 $5 | $R0
    DetailPrint "tapinstall update returned: $R0"
    Goto tapinstall_check_error

 tapinstall:
    DetailPrint "TAP REMOVE OLD TAP"

    nsExec::ExecToLog '"$INSTDIR\openvpn\driver\tapinstall.exe" remove TAP0801'
    Pop $R0 # return value/error/timeout
    DetailPrint "tapinstall remove TAP0801 returned: $R0"

    DetailPrint "TAP INSTALL (${TAP})"
    nsExec::ExecToLog '"$INSTDIR\openvpn\driver\tapinstall.exe" install "$INSTDIR\openvpn\driver\OemWin2k.inf" ${TAP}'
    Pop $R0 # return value/error/timeout
    ;Call CheckReboot
    IntOp $5 $5 | $R0
    DetailPrint "tapinstall install returned: $R0"

 tapinstall_check_error:
    DetailPrint "tapinstall cumulative status: $5"
    IntCmp $5 0 notap
    MessageBox MB_OK "An error occurred installing the TAP device driver."
notap:

SectionEnd


# uninstaller section start
section "uninstall"
    # first, delete the uninstaller
    delete "$INSTDIR\uninstall.exe"

    DetailPrint "TAP REMOVE"
    DetailPrint '"$INSTDIR\openvpn\driver\tapinstall.exe" remove ${TAP}'
    nsExec::ExecToLog '"$INSTDIR\openvpn\driver\tapinstall.exe" remove ${TAP}'
    Pop $R0 # return value/error/timeout
    DetailPrint "tapinstall remove returned: $R0"
 
    # Remove from Add/Remove Programs from the Control Panel
    DeleteRegValue HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Product" "DisplayName"
    DeleteRegValue HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Product" "UninstallString"
    DeleteRegValue HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Product" "NoModify"
    DeleteRegValue HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\Product" "NoRepair"

    # Remove autostart entry
    DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "Mullvad"
    nsExec::Exec 'schtasks /Delete /tn Mullvad /F'

    # Remove firewall rules
    nsExec::ExecToLog 'netsh advfirewall firewall delete rule name="MullvadICMP11"'
    nsExec::ExecToLog 'netsh advfirewall firewall delete rule name="MullvadOpenVPN"'
    nsExec::ExecToLog 'netsh advfirewall firewall delete rule name="MullvadMaster"'
    nsExec::ExecToLog 'netsh advfirewall firewall delete rule name="BlockIPv6_low"'
    nsExec::ExecToLog 'netsh advfirewall firewall delete rule name="BlockIPv6_high"'

    # second, remove the link from the start menu
    delete "$SMPROGRAMS\Mullvad.lnk"
 
    # Delete everything
    rmdir /r /REBOOTOK "$INSTDIR"

# uninstaller section end
sectionEnd

