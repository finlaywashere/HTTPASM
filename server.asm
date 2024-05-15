bits 64

%define  swap_word(x)  ( (x<<8) | ((x&0xFFFF)>>>8) )

section .text

HTTP_PORT EQU 8080
BACKLOG EQU 5
STDOUT EQU 1
BUFFER_LEN EQU 200
FILE_BUFFER_LEN EQU 1000

AF_INET EQU 2
SOCK_STREAM EQU 1

SYS_SOCKET EQU 41
SYS_WRITE EQU 1
SYS_EXIT EQU 60
SYS_BIND EQU 49
SYS_LISTEN EQU 50
SYS_ACCEPT EQU 43
SYS_READ EQU 0
SYS_OPEN EQU 2
SYS_CLOSE EQU 3
SYS_LSEEK EQU 8
SYS_SETSOCKOPT EQU 54

SEEK_SET EQU 0
SEEK_END EQU 2
O_RDONLY EQU 0

SOL_SOCKET EQU 1
SO_REUSEADDR EQU 2

global _start
_start:
    ; Create a socket
    mov rax, SYS_SOCKET
    mov rdi, AF_INET
    mov rsi, SOCK_STREAM
    mov rdx, 0
    syscall
    ; RAX now contains fd
    mov rbx, rax
    cmp rax, -1
    jne .no_sock_err
.sock_err:
    mov rax, socket_error_msg
    call print_text
    mov rax, 1
    call exit
.no_sock_err:
    mov rax, SYS_SETSOCKOPT
    mov rdi, rbx
    mov rsi, SOL_SOCKET
    mov rdx, SO_REUSEADDR
    mov r10, sockopt
    mov r8, 4
    ; Do bind
    mov rax, SYS_BIND
    mov rdi, rbx
    mov rsi, sockaddr
    mov rdx, 16
    syscall
    cmp rax, 0
    jne .sock_err ; Failed to bind
    mov rax, SYS_LISTEN
    mov rdi, rbx
    mov rsi, BACKLOG
    syscall
    cmp rax, 0
    jne .sock_err ; Failed to listen
    mov rax, bind_success_msg
    call print_text
.accept:
    mov rax, SYS_ACCEPT
    mov rdi, rbx
    mov rsi, client_sock
    mov rdx, client_addrlen
    syscall
    cmp rax, 0
    jl .accept_error
    push rax
    mov rax, accept_success_msg
    call print_text
    pop rax
    push rax
    mov rcx, rax
    mov rax, SYS_READ
    mov rdi, rcx
    mov rsi, input_buffer
    mov rdx, BUFFER_LEN
    syscall
    pop rax
    call handle_request
    jmp .accept
.accept_error:
    mov rax, accept_error_msg
    call print_text
    jmp .accept

handle_request: ; GET /test.txt HTTP 1.1
    push r8
    mov r8, rax
    push rax
    push rbx
    push rcx
    push rdx

    mov rax, -1 ; RAX sentinel
    mov rbx, input_buffer
    mov rcx, 0
.request_loop:
    cmp rax, -1
    jne .request_find_end
    mov dl, [rbx]
    cmp dl, 0x20 ; Check for space
    jne .request_loop_inc
    mov rax, rcx
    inc rax ; Remove space
    inc rax ; Remove leading slash
    jmp .request_loop_inc
.request_find_end:
    mov dl, [rbx]
    cmp dl, 0x20 ; Check for space
    je .request_found_end
    cmp dl, 0xD ; Carriage return
    je .request_found_end
    cmp dl, 0xA ; New line
    je .request_found_end
    jmp .request_loop_inc
.request_found_end:
    mov rbx, input_buffer
    add rbx, rax
    sub rcx, rax
    mov rax, rbx
    mov rbx, rcx
    push rdx
    mov rdx, rax
    add rdx, rbx
    push r11
    mov r11b, 0x0
    mov [rdx], r11b
    pop r11
    pop rdx
    call process_get
    pop rdx
    pop rcx
    pop rbx
    pop rax
    pop r8
    ret
.request_loop_inc:
    inc rbx
    inc rcx
    cmp rcx, 200
    jl .request_loop

    mov rax, request_fail_msg
    call print_text

    pop rdx
    pop rcx
    pop rbx
    pop rax
    pop r8
    ret

process_get: ; Takes string in RAX, length in RBX, and file handle in R8
    push rax
    push rdi
    push rsi
    push rdx
    push rbx
    push r8
    push r9
    push r10
    push r11
    push r12
    mov r9, rax
    mov rax, get_message
    call print_text
    mov rax, r9
    call print_text
    mov rax, newline
    call print_text
    mov r10, rbx
    mov rax, SYS_OPEN
    mov rdi, r9
    mov rsi, O_RDONLY
    mov rdx, 0
    syscall
    cmp rax, 0
    jl .get_404
    mov r12, rax

    mov rax, SYS_LSEEK
    mov rdi, r12
    mov rsi, 0 ; 0 offset
    mov rdx, SEEK_END
    syscall
    mov r11, rax
    push r11
    mov rax, SYS_LSEEK
    mov rdi, r12
    mov rsi, 0
    mov rdx, SEEK_SET
    syscall
    mov rax, http_response_200
    call strlen
    mov rdx, rax
    mov rsi, http_response_200
    mov rdi, r8
    mov rax, SYS_WRITE
    syscall
.get_read:
    mov rax, SYS_READ
    mov rdi, r12
    mov rsi, file_buffer
    mov rdx, FILE_BUFFER_LEN
    syscall
    pop r11
    sub r11, rax
    push r11
    mov rdx, rax
    mov rsi, file_buffer
    mov rdi, r8
    mov rax, SYS_WRITE
    syscall
    pop r11
    cmp r11, 0
    push r11
    jg .get_read
    pop r11
    mov rax, SYS_CLOSE
    mov rdi, r12
    syscall

    jmp .get_end
.get_404:
    mov rax, http_response_404
    call strlen
    mov rdx, rax
    mov rsi, http_response_404
    mov rax, SYS_WRITE
    mov rdi, r8
    syscall
.get_end:
    mov rax, SYS_CLOSE
    mov rdi, r8
    syscall
    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rbx
    pop rdx
    pop rsi
    pop rdi
    pop rax
    ret

strlen: ; Buffer location in RAX
    push rbx
    push rcx
    push rdx
    mov rcx, 0
.strlen_loop:
    mov rdx, [rax]
    cmp dl, 0x0
    je .strlen_loopend
    inc rax
    inc rcx
    jmp .strlen_loop
.strlen_loopend:
    mov rax, rcx
    pop rdx
    pop rcx
    pop rbx
    ret

print_withlen: ; Buffer location in RAX, length in RBX
    push rdi
    push rsi
    push rdx
    push rax

    mov rsi, rax
    mov rdx, rbx
    mov rax, SYS_WRITE
    mov rdi, STDOUT
    syscall

    pop rax
    pop rdx
    pop rsi
    pop rdi
    ret

print_text: ; Buffer location in RAX
    push rbx
    push rax

    call strlen
    mov rbx, rax
    pop rax
    push rax
    call print_withlen
    pop rax
    pop rbx
    ret

exit: ; Error code in RAX
    mov rdi, rax
    mov rax, SYS_EXIT
    syscall

section .data
socket_error_msg:
    db "Failed to bind to socket!", 0xA, 0x0
bind_success_msg:
    db "Successfully bound! Listening!", 0xA, 0x0
accept_error_msg:
    db "Failed to accept connection!", 0xA, 0x0
accept_success_msg:
    db "Accepted connection!", 0xA, 0x0
request_fail_msg:
    db "Failed to parse request!", 0xA, 0x0
http_response_200:
    db "HTTP/1.1 200 OK", 0xA, "Server: HTTPASM", 0xA, "Content-Type: text/html", 0xA, 0xA, 0x0
http_response_404:
    db "HTTP/1.1 404 File Not Found", 0xA, "Server: HTTPASM", 0xA, "Content-Type: text/html", 0xA, 0xA, "404 File Not Found", 0xA, 0x0
newline:
    db 0xA, 0x0
get_message:
    db "Received request: ", 0x0
sockaddr:
    dw AF_INET
    dw swap_word(HTTP_PORT)
    dd 0
    dq 0
sockopt:
    dd 1
section .bss
input_buffer:
    resb BUFFER_LEN
file_buffer:
    resb FILE_BUFFER_LEN
client_sock:
    resb 8
client_addrlen:
    resd 1
