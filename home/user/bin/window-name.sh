#!/bin/sh
echo "click in window to show its name..."
name=$(xprop WM_CLASS)
echo ${name}

