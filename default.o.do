redo-ifchange ${$1%.o}.porth
bwrap --bind / / --bind $3 $(pwd)/output.o --bind $(mktemp /tmp/XXXXXX) $(pwd)/output ./porth com ${$1%.o}.porth