--- PROFESSIONAL PENTEST BRIEF ---

Target: 10.10.10.10
Hunter: 10.10.14.2
URL: http://10.10.10.10:80
Ports: 22,80,445

Services:
- 22/tcp: SSH (OpenSSH 8.4p1)
- 80/tcp: HTTP (Apache 2.4.41)
- 445/tcp: SMB (Samba 4.13)

Recommended Next Steps:
1. SSH: Try default laeks or known leaks.
2. HTTP: Run gobuster for directory discovery.
3. SMB: Check for anonymous share access.
