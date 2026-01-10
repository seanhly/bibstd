#!/bin/bash
set -e
echo "Compiling BibTeX compiler..."
make clean && make
echo "Running compiler on sample.bib:"
./dist/bibtex_compiler < test/sample.bib
if [ $? -ne 0 ]; then
    echo -e "[\033[0;31mFAILED\033[0m] Test 1 (sample.bib)."
else
    echo -e "[\033[0;32mPASSED\033[0m] Test 1 (sample.bib)."
fi
./dist/bibtex_compiler < test/A_Theory_of_Justice.bibtex
if [ $? -ne 0 ]; then
    echo -e "[\033[0;31mFAILED\033[0m] Test 2 (A_Theory_of_Justice.bibtex)."
else
    echo -e "[\033[0;32mPASSED\033[0m] Test 2 (A_Theory_of_Justice.bibtex)."
fi
./dist/bibtex_compiler < test/big_file.bib
if [ $? -ne 0 ]; then
    echo -e "[\033[0;31mFAILED\033[0m] Test 3 (big_file.bib)."
else
    echo -e "[\033[0;32mPASSED\033[0m] Test 3 (big_file.bib)."
fi
echo "All tests completed."
