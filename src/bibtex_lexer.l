%{
#include "bibtex_parser.hpp"
#include <string>
#include <cstring>
extern int yylineno;
extern YYLTYPE yylloc;
static int yycolumn = 1;

#define SET_LOC(len) \
	do { \
		yylloc.first_line = yylineno; \
		yylloc.first_column = yycolumn; \
		yylloc.last_line = yylineno; \
		yylloc.last_column = yycolumn + (len) - 1; \
		yycolumn += (len); \
	} while (0)

static void set_loc_for_text(const std::string& text) {
	const int start_line = yylineno;
	const int start_col = yycolumn;
	int line = yylineno;
	int col = yycolumn;
	int last_line = line;
	int last_col = col;
	for (char ch : text) {
		last_line = line;
		last_col = col;
		if (ch == '\n') {
			line++;
			col = 1;
		} else {
			col++;
		}
	}

	yylineno = line;
	yycolumn = col;
	yylloc.first_line = start_line;
	yylloc.first_column = start_col;
	yylloc.last_line = last_line;
	yylloc.last_column = last_col;
}
%}

%option noyywrap
%option yylineno

%x VALUE

%%
"@"                { SET_LOC(yyleng); return AT; }
"{"                { SET_LOC(yyleng); return LBRACE; }
"}"                { SET_LOC(yyleng); return RBRACE; }
","                { SET_LOC(yyleng); return COMMA; }
"="                { SET_LOC(yyleng); BEGIN(VALUE); return EQUALS; }
"#"                { SET_LOC(yyleng); return HASH; }

[a-zA-Z0-9_][a-zA-Z0-9_.:;\-!?+*/]*   { SET_LOC(yyleng); yylval.str = new std::string(yytext); return IDENT; }

\"[^\"]*\"   { SET_LOC(yyleng); yylval.str = new std::string(yytext); return STRING; }

[%][^\n]*          { /* inline or full-line comment starting with %: ignore to EOL */ yycolumn += yyleng; }

[ \t\r]+           { /* skip whitespace, update column */ yycolumn += yyleng; }

\n+                 { /* newline: increment line is handled by flex when %option yylineno is used */ yycolumn = 1; }

.                   { SET_LOC(yyleng); return yytext[0]; }

<VALUE>[ \t\r]+           { yycolumn += yyleng; }
<VALUE>\n+                { yycolumn = 1; }

<VALUE>[%][^\n]*          { /* comment inside value: ignore to EOL */ yycolumn += yyleng; }

<VALUE>\"[^\"]*\"   { SET_LOC(yyleng); yylval.str = new std::string(yytext); BEGIN(INITIAL); return STRING; }
<VALUE>[a-zA-Z0-9_][a-zA-Z0-9_.:;\-!?+*/]*   { SET_LOC(yyleng); yylval.str = new std::string(yytext); BEGIN(INITIAL); return IDENT; }

<VALUE>"{" {
	std::string text;
	text.push_back('{');
	int depth = 1;
	while (depth > 0) {
		const int c = yyinput();
		if (c == EOF) break;
		text.push_back(static_cast<char>(c));
		if (c == '{') depth++;
		else if (c == '}') depth--;
	}
	set_loc_for_text(text);
	yylval.str = new std::string(text);
	BEGIN(INITIAL);
	return STRING;
}

<VALUE>. { SET_LOC(yyleng); BEGIN(INITIAL); return yytext[0]; }

%%

