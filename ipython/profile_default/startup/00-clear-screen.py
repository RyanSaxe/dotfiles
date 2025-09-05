#!/usr/bin/env python3
"""
IPython startup script to clear the terminal and provide a clean interface.
This script runs automatically when IPython starts and clears any startup
warnings or messages, leaving only a clean prompt starting at [1].
"""

import os
import sys

# Clear the terminal screen using ANSI escape sequences
# This works on both Unix/Linux/macOS and Windows terminals
if os.name == 'posix':  # Unix/Linux/macOS
    os.system('clear')
elif os.name == 'nt':   # Windows
    os.system('cls')
else:
    # Fallback: use ANSI escape sequence for clearing screen
    print('\033[2J\033[H', end='')

# Optional: Print a clean welcome message (remove if you don't want any output)
# print("IPython ready")