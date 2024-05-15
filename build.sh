#!/bin/bash
rm -f server server.o
nasm -f elf64 -o server.o server.asm
ld -o server server.o
