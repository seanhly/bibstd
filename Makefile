CXX=g++
LEX=flex
YACC=bison
CXXFLAGS?=-std=c++17
# GCC 13+ can warn on Bison skeleton code even though it's guarded by `if (yyss != yyssa)`.
CXXWARN?=-Wno-free-nonheap-object
SRCDIR=src
DISTDIR=dist
$(shell mkdir -p $(DISTDIR))
all: $(DISTDIR)/bibtex_compiler
$(DISTDIR)/bibtex_lexer.cpp: $(SRCDIR)/bibtex_lexer.l
	$(LEX) -o $(DISTDIR)/bibtex_lexer.cpp $(SRCDIR)/bibtex_lexer.l
$(DISTDIR)/bibtex_parser.cpp $(DISTDIR)/bibtex_parser.hpp: $(SRCDIR)/bibtex_parser.y
	$(YACC) -d -o $(DISTDIR)/bibtex_parser.cpp $(SRCDIR)/bibtex_parser.y
$(DISTDIR)/bibtex_compiler: $(DISTDIR)/bibtex_lexer.cpp $(DISTDIR)/bibtex_parser.cpp $(DISTDIR)/bibtex_parser.hpp
	$(CXX) $(CXXFLAGS) $(CXXWARN) -o $(DISTDIR)/bibtex_compiler $(DISTDIR)/bibtex_lexer.cpp $(DISTDIR)/bibtex_parser.cpp
clean:
	rm -f $(DISTDIR)/bibtex_lexer.cpp $(DISTDIR)/bibtex_parser.cpp $(DISTDIR)/bibtex_parser.hpp $(DISTDIR)/bibtex_compiler
