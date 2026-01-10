%{
#include <map>
#include <string>
#include <vector>
#include <iostream>
#include <algorithm>
#include <cctype>
#include <cstddef>

#include <set>
#include <cstdlib>

int yylex(void);
void yyerror(const char* s);

struct BibEntry {
    std::string type;
    std::string key;
    std::map<std::string, std::string> fields;
};
std::vector<BibEntry> entries;

static const std::size_t WRAP_COLUMNS = 80;

// Preferred ordering of fields when printing.
static const char* FIELD_ORDER[] = {
    "title", "author", "year", "pages", "volume", "journal","publisher", "number",
    "url", "booktitle", "mrnumber", "mrclass", "eprint", "issn", "doi", "fjournal",
    "mrreviewer", "series", "isbn", "date", "organization", "note",
    "month", "archiveprefix", "school", "editor", "primaryclass", "coden", "address",
    "edition", "location", "howpublished", "page", "eprinttype", "chapter", "type",
    "timestamp", "shortjournal", "pdf", "origpublisher", "origdate", "institution",
    "eprintclass", "biburl", "bibsource", "urldate", "translator", "subtitle",
    "shortseries", "place", "origlocation", "origlanguage", "lccn", "label", "keywords",
    "issue_date", "ignorepdf", "hal_version", "hal_id", "eventtitle", "eventdate",
    "abstract"
};
static const std::size_t FIELD_ORDER_COUNT = sizeof(FIELD_ORDER) / sizeof(FIELD_ORDER[0]);

// Required fields per entry type.
static const std::vector<std::string> REQUIRED_ARTICLE_FIELDS   = {"author", "title", "year"};
static const std::set<std::string> REQUIRED_ARTICLE_JOURNAL_OR_HOWPUBLISHED = {"journal", "howpublished"};
// TODO enable extra field checks via a --strict flag
static const std::vector<std::string> REQUIRED_BOOK_FIELDS      = {"title", /* "publisher", */ "year"};
static const std::vector<std::string> REQUIRED_INPROC_FIELDS    = {"author", "title", "booktitle", "year"};
static const std::vector<std::string> REQUIRED_INCOLL_FIELDS    = {"author", "title", "booktitle", "publisher", "year"};
static const std::vector<std::string> REQUIRED_THESIS_FIELDS    = {"author", "title", "school", "year"};
static const std::vector<std::string> REQUIRED_TECHREPORT_FIELDS= {"author", "title", "institution", "year"};
static const std::vector<std::string> REQUIRED_BOOKLET_FIELDS   = {"title"};
static const std::set<std::string> REQUIRED_BOOK_AUTHOR_OR_EDITOR = {"author", "editor"};

// Map from (lowercased) field name to its rank in FIELD_ORDER.
static std::map<std::string, int> field_order_index;

static std::string to_lower_copy(const std::string& s) {
    std::string r = s;
    std::transform(r.begin(), r.end(), r.begin(),
                   [](unsigned char c) { return std::tolower(c); });
    return r;
}

static std::string trim(const std::string& s) {
    std::size_t start = 0;
    while (start < s.size() && std::isspace(static_cast<unsigned char>(s[start]))) {
        ++start;
    }
    std::size_t end = s.size();
    while (end > start && std::isspace(static_cast<unsigned char>(s[end - 1]))) {
        --end;
    }
    return s.substr(start, end - start);
}

static std::string normalize_one_author(const std::string& name) {
    const std::string t = trim(name);
    if (t.empty()) return t;

    // Count commas to distinguish formats.
    int comma_count = 0;
    for (char c : t) {
        if (c == ',') ++comma_count;
    }

    if (comma_count == 0) {
        // Already in "First Last" style.
        return t;
    }

    // Split by commas.
    std::vector<std::string> parts;
    std::size_t pos = 0;
    while (true) {
        std::size_t comma = t.find(',', pos);
        if (comma == std::string::npos) {
            parts.push_back(trim(t.substr(pos)));
            break;
        }
        parts.push_back(trim(t.substr(pos, comma - pos)));
        pos = comma + 1;
    }

    if (parts.size() == 2) {
        // "Last, First" -> "First Last".
        const std::string& last = parts[0];
        const std::string& first = parts[1];
        return first + " " + last;
    }
    if (parts.size() >= 3) {
        // "Last, Suffix, First" (ignore any extra commas beyond the first three).
        const std::string& last = parts[0];
        const std::string& suffix = parts[1];
        const std::string& first = parts[2];
        // Canonical: "First Last Suffix".
        return first + " " + last + " " + suffix;
    }

    return t;
}

static std::string normalize_author_inner(const std::string& inner) {
    std::vector<std::string> authors;
    std::size_t pos = 0;
    const std::string and_tok = " and ";
    const std::string lower_inner = to_lower_copy(inner);
    const std::string and_tok_lower = to_lower_copy(and_tok);
    while (true) {
        std::size_t p = lower_inner.find(and_tok_lower, pos);
        if (p == std::string::npos) {
            authors.push_back(trim(inner.substr(pos)));
            break;
        }
        authors.push_back(trim(inner.substr(pos, p - pos)));
        pos = p + and_tok.size();
    }

    std::string result;
    bool first = true;
    for (const auto& a : authors) {
        if (a.empty()) continue;
        std::string norm = normalize_one_author(a);
        if (!first) {
            result += " and ";
        }
        result += norm;
        first = false;
    }
    return result;
}

static std::string normalize_author_value(const std::string& raw) {
    std::string s = trim(raw);
    std::string inner;
    if (s.size() >= 2 &&
        ((s.front() == '{' && s.back() == '}') ||
         (s.front() == '"' && s.back() == '"'))) {
        inner = s.substr(1, s.size() - 2);
    } else {
        inner = s;
    }

    std::string canon_inner = normalize_author_inner(inner);
    return "{" + canon_inner + "}";
}

static void init_field_order() {
    if (!field_order_index.empty()) return;
    for (std::size_t i = 0; i < FIELD_ORDER_COUNT; ++i) {
        field_order_index[FIELD_ORDER[i]] = static_cast<int>(i);
    }
}

static int field_rank_of(const std::string& name) {
    const std::string lower = to_lower_copy(name);
    auto it = field_order_index.find(lower);
    if (it != field_order_index.end()) {
        return it->second;
    }
    // Unknown fields come after all known ones, sorted by name.
    return static_cast<int>(FIELD_ORDER_COUNT);
}

// --- Helpers for generating canonical entry IDs ---

static std::string strip_outer_braces_or_quotes(const std::string& s) {
    std::string t = trim(s);
    if (t.size() >= 2 &&
        ((t.front() == '{' && t.back() == '}') ||
         (t.front() == '"' && t.back() == '"'))) {
        return t.substr(1, t.size() - 2);
    }
    return t;
}

static std::string get_field_value(const BibEntry& e, const char* name) {
    const std::string target = to_lower_copy(name);
    for (const auto& kv : e.fields) {
        if (to_lower_copy(kv.first) == target) {
            return kv.second;
        }
    }
    return std::string();
}

static bool is_title_stop_word(const std::string& w) {
    static const char* STOP_WORDS[] = {
        "a", "an", "the", "of", "in", "on", "and", "for", "to", "with",
        "from", "by", "about", "into", "over", "after", "before", "between",
        "without", "within"
    };
    static const std::size_t N = sizeof(STOP_WORDS) / sizeof(STOP_WORDS[0]);

    const std::string lower = to_lower_copy(w);
    for (std::size_t i = 0; i < N; ++i) {
        if (lower == STOP_WORDS[i]) return true;
    }
    return false;
}

static std::string first_content_word_from_title(const std::string& raw_title) {
    const std::string inner = strip_outer_braces_or_quotes(raw_title);
    std::string word;
    std::vector<std::string> words;
    for (char ch : inner) {
        if (std::isalnum(static_cast<unsigned char>(ch))) {
            word.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(ch))));
        } else {
            if (!word.empty()) {
                words.push_back(word);
                word.clear();
            }
        }
    }
    if (!word.empty()) {
        words.push_back(word);
    }

    for (const auto& w : words) {
        if (!is_title_stop_word(w)) {
            return w;
        }
    }
    return words.empty() ? std::string() : words.front();
}

static std::string second_content_word_from_title(const std::string& raw_title) {
    const std::string inner = strip_outer_braces_or_quotes(raw_title);
    std::string word;
    std::vector<std::string> words;
    for (char ch : inner) {
        if (std::isalnum(static_cast<unsigned char>(ch))) {
            word.push_back(static_cast<char>(std::tolower(static_cast<unsigned char>(ch))));
        } else {
            if (!word.empty()) {
                words.push_back(word);
                word.clear();
            }
        }
    }
    if (!word.empty()) words.push_back(word);
    int content_word_count = 0;
    for (const auto& w : words) {
        if (!is_title_stop_word(w)) {
            ++content_word_count;
            if (content_word_count == 2) return w;
        }
    }
    return std::string();
}

static std::string lead_author_surname(const std::string& raw_author) {
    std::string inner = strip_outer_braces_or_quotes(raw_author);
    const std::string and_tok = " and ";
    const std::string lower_inner = to_lower_copy(inner);
    const std::string and_tok_lower = to_lower_copy(and_tok);
    std::size_t p = lower_inner.find(and_tok_lower);
    if (p != std::string::npos)
        inner = inner.substr(0, p);
    inner = trim(inner);
    if (inner.empty()) return std::string();
    // Inner is now canonical "First Last [Suffix]" from normalization.
    std::string surname;
    std::string current;
    for (char ch : inner) {
        if (std::isspace(static_cast<unsigned char>(ch))) {
            if (!current.empty()) {
                surname = current;
                current.clear();
            }
        } else current.push_back(ch);
    }
    if (!current.empty())
        surname = current;
    // Remove problematic characters when forming IDs: "'.=\^{}~
    const std::string bad_chars = "\"'.=\\^{}~";
    std::string cleaned;
    for (char ch : surname)
        if (bad_chars.find(ch) == std::string::npos)
            cleaned.push_back(ch);
    return to_lower_copy(cleaned);
}

static std::string extract_year_digits(const std::string& raw_year) {
    const std::string s = strip_outer_braces_or_quotes(raw_year);
    std::string digits;
    for (char ch : s) {
        if (std::isdigit(static_cast<unsigned char>(ch)))
            digits.push_back(ch);
        else if (!digits.empty()) break;
    }
    if (digits.size() > 4) digits = digits.substr(0, 4);
    return digits;
}

static bool is_year_only_date(const std::string& raw) {
    const std::string s = strip_outer_braces_or_quotes(raw);
    if (s.size() != 4) return false;
    for (char ch : s)
        if (!std::isdigit(static_cast<unsigned char>(ch))) return false;
    return true;
}

// Forward declaration for helper used below.
static bool has_field(const BibEntry& e, const std::string& name);

// If `date` is of the form YYYY-MM and there are no
// explicit `year` or `month` fields yet, replace that
// single `date` field with separate `year` and `month`.
static void split_year_month_from_date(BibEntry& e) {
    if (has_field(e, "year") || has_field(e, "month"))
        return;

    auto it_date = e.fields.end();
    for (auto it = e.fields.begin(); it != e.fields.end(); ++it) {
        if (to_lower_copy(it->first) == "date") {
            it_date = it;
            break;
        }
    }
    if (it_date == e.fields.end()) return;

    const std::string inner = strip_outer_braces_or_quotes(it_date->second);
    std::string year;
    std::string month;

    std::size_t i = 0;
    while (i < inner.size() && std::isdigit(static_cast<unsigned char>(inner[i]))) {
        year.push_back(inner[i]);
        ++i;
    }
    if (year.size() != 4) return;
    if (i >= inner.size() || inner[i] != '-') return;
    ++i;
    while (i < inner.size() && std::isdigit(static_cast<unsigned char>(inner[i]))) {
        month.push_back(inner[i]);
        ++i;
    }
    if (month.empty()) return;
    if (i != inner.size()) return; // extra trailing characters, not pure YYYY-MM

    // Basic month range check (1-12).
    int month_num = std::atoi(month.c_str());
    if (month_num < 1 || month_num > 12) return;

    // All conditions satisfied: rewrite fields.
    e.fields.erase(it_date);
    e.fields["year"] = year;
    // Store month without zero-padding (e.g. "01" -> "1").
    e.fields["month"] = std::to_string(month_num);
}

// Normalize existing month fields so they are not zero-padded.
static void normalize_month_in_entry(BibEntry& e) {
    for (auto& kv : e.fields) {
        if (to_lower_copy(kv.first) != "month") continue;
        const std::string inner = strip_outer_braces_or_quotes(kv.second);
        if (inner.empty()) continue;
        bool all_digits = true;
        for (char ch : inner) {
            if (!std::isdigit(static_cast<unsigned char>(ch))) {
                all_digits = false;
                break;
            }
        }
        if (!all_digits) continue;

        // Strip leading zeros but leave a single zero if that's all there is.
        std::size_t pos = 0;
        while (pos + 1 < inner.size() && inner[pos] == '0') ++pos;
        const std::string normalized = inner.substr(pos);
        kv.second = normalized;
    }
}

static bool has_field(const BibEntry& e, const std::string& name) {
    const std::string target = to_lower_copy(name);
    for (const auto& kv : e.fields)
        if (to_lower_copy(kv.first) == target) return true;
    return false;
}

static bool has_any_field(const BibEntry& e, const std::set<std::string>& names) {
    for (const auto& kv : e.fields)
        if (names.count(to_lower_copy(kv.first))) return true;
    return false;
}

static std::string join(const std::vector<std::string>& v, const std::string& sep) {
    std::string res;
    for (std::size_t i = 0; i < v.size(); ++i) {
        if (i > 0) res += sep;
        res += v[i];
    }
    return res;
}

static bool check_required_fields(const BibEntry& e, std::string& error) {
    std::string type = to_lower_copy(e.type);
    std::vector<std::string> missing;

    if (type == "article") {
        /* TODO enable via a --strict flag
        if (!has_any_field(e, REQUIRED_ARTICLE_JOURNAL_OR_HOWPUBLISHED))
            missing.push_back("journal or howpublished");
        */
        for (const auto& f : REQUIRED_ARTICLE_FIELDS)
            if (!has_field(e, f)) missing.push_back(f);
    } else if (type == "book") {
        if (!has_any_field(e, REQUIRED_BOOK_AUTHOR_OR_EDITOR))
            missing.push_back("author or editor");
        for (const auto& f : REQUIRED_BOOK_FIELDS)
            if (!has_field(e, f)) missing.push_back(f);
    } else if (type == "inproceedings") {
        for (const auto& f : REQUIRED_INPROC_FIELDS)
            if (!has_field(e, f)) missing.push_back(f);
    } else if (type == "incollection") {
        for (const auto& f : REQUIRED_INCOLL_FIELDS)
            if (!has_field(e, f)) missing.push_back(f);
    } else if (type == "phdthesis" || type == "mastersthesis") {
        for (const auto& f : REQUIRED_THESIS_FIELDS)
            if (!has_field(e, f)) missing.push_back(f);
    } else if (type == "techreport") {
        for (const auto& f : REQUIRED_TECHREPORT_FIELDS)
            if (!has_field(e, f)) missing.push_back(f);
    } else if (type == "booklet") {
        for (const auto& f : REQUIRED_BOOKLET_FIELDS)
            if (!has_field(e, f)) missing.push_back(f);
    }

    if (!missing.empty()) {
        error = join(missing, ", ");
        return false;
    }
    return true;
}

static std::string generate_id(const BibEntry& e) {
    const std::string title = get_field_value(e, "title");
    const std::string author = get_field_value(e, "author");
    const std::string year = get_field_value(e, "year");
    const std::string word = first_content_word_from_title(title);
    const std::string second_word = second_content_word_from_title(title);
    std::string keywords;
    if (second_word.empty())
        keywords = word;
    else {

        // Append second word to first word to reduce collisions.
        // But make first letter of second word uppercase to improve readability.
        keywords = word + static_cast<char>(
            std::toupper(static_cast<unsigned char>(second_word[0]))
        ) + second_word.substr(1);
    }
    const std::string surname = lead_author_surname(author);
    const std::string year_digits = extract_year_digits(year);
    if (keywords.empty() || year_digits.empty())
        return e.key;
    if (surname.empty())
        return keywords + year_digits;
    return surname + year_digits + keywords;
}

static bool contains_advertising_link(const std::string& raw) {
    const std::string inner = strip_outer_braces_or_quotes(raw);
    const std::string lower = to_lower_copy(inner);
    static const char* BAD_DOMAINS[] = {
        "books.google.",
        "jstor.org",
        "researchgate.net",
        "openresearchlibrary.org",
        "semanticscholar.org"
    };
    static const std::size_t N = sizeof(BAD_DOMAINS) / sizeof(BAD_DOMAINS[0]);
    for (std::size_t i = 0; i < N; ++i) {
        if (lower.find(BAD_DOMAINS[i]) != std::string::npos) return true;
    }
    return false;
}

static bool should_suppress_field(const std::string& name, const std::string& value) {
    const std::string lower_name = to_lower_copy(name);
    if (lower_name == "url" || lower_name == "note")
        if (contains_advertising_link(value)) return true;
    return false;
}

static void print_wrapped_field(const std::string& name, const std::string& value) {
    // Short or unbraced: print on one line.
    if (value.size() == 0 || value.front() != '{' || value.back() != '}') {
        if (value.front() == '"' && value.back() == '"') {
            const std::string inner = value.substr(1, value.size() - 2);
            std::cout << "\t" << name << "={" << inner << "}";
        } else std::cout << "\t" << name << "={" << value << "}";
    } else if (value.size() <= WRAP_COLUMNS) {
        std::cout << "\t" << name << "=" << value;
    } else {
        const std::string inner = value.substr(1, value.size() - 2);
        // Open brace on its own line after the field name.
        std::cout << "\t" << name << "={\n";
        std::size_t pos = 0;
        const std::size_t n = inner.size();
        while (pos < n) {
            while (pos < n && inner[pos] == ' ')
                ++pos;
            if (pos >= n) break;
            std::size_t end = pos + WRAP_COLUMNS;
            if (end >= n)
                end = n;
            else {
                std::size_t space_pos = inner.rfind(' ', end);
                if (space_pos != std::string::npos && space_pos > pos)
                    end = space_pos;
            }
            std::string line = inner.substr(pos, end - pos);
            std::size_t first_non_space = line.find_first_not_of(' ');
            if (first_non_space != std::string::npos)
                line.erase(0, first_non_space);
            std::cout << "\t\t" << line << "\n";
            pos = end;
        }
        // Closing brace on its own line, indented once.
        std::cout << "\t}";
    }
}
%}

%code requires {
    #include <map>
    #include <string>

    #ifndef YYLTYPE_IS_DECLARED
    #define YYLTYPE_IS_DECLARED 1
    typedef struct YYLTYPE {
        int first_line;
        int first_column;
        int last_line;
        int last_column;
    } YYLTYPE;
    #endif
}

%locations

%union {
    std::string* str;
    std::map<std::string, std::string>* fieldmap;
}

%token <str> IDENT STRING NUMBER
%token AT LBRACE RBRACE COMMA EQUALS HASH
%type <fieldmap> fields field
%type <str> value

%%
bibtex : entries { /* done */ }
;

entries : entries entry
        | entry
;

entry : AT IDENT LBRACE IDENT COMMA fields RBRACE {
    BibEntry e;
    e.type = *$2;
    e.key = *$4;
    e.fields = *$6;
    entries.push_back(e);
    delete $2; delete $4; delete $6;
}
;

fields : fields COMMA field { $$ = $1; $$->insert($3->begin(), $3->end()); delete $3; }
       | field { $$ = $1; }
       // Allow trailing comma
       | fields COMMA { $$ = $1; }
;

field : IDENT EQUALS value {
    $$ = new std::map<std::string, std::string>();
    std::string name = *$1;
    std::string value = *$3;
    if (to_lower_copy(name) == "author")
        value = normalize_author_value(value);
    if (to_lower_copy(name) == "date" && is_year_only_date(value))
        name = "year";
    if (to_lower_copy(name) == "journaltitle")
        name = "journal";
    (*$$)[name] = value;
    delete $1; delete $3;
}
;

value : STRING { $$ = $1; }
      | NUMBER { $$ = $1; }
      | IDENT  { $$ = $1; }
;

%%

void yyerror(const char* s) {
    extern YYLTYPE yylloc;
    std::cerr << "parse error at " << yylloc.first_line << ":" << yylloc.first_column << ": " << s << "\n";
}

int main() {
    init_field_order();
    yyparse();
    // Normalize date/month fields
    for (auto& e : entries) {
        split_year_month_from_date(e);
        normalize_month_in_entry(e);
    }
    // Check required fields for each entry
    for (const auto& e : entries) {
        std::string error;
        if (!check_required_fields(e, error)) {
            std::cerr << "@" << e.type << "{" << e.key << "} requires fields: " << error << std::endl;
            return 1;
        }
    }
    for (const auto& e : entries) {
        std::string type_l = to_lower_copy(e.type);
        const std::string id = generate_id(e);
        std::cout << "@" << type_l << "{" << id;
        // Copy fields into a vector and sort by preferred order, then name.
        std::vector<std::pair<std::string, std::string>> ordered_fields(
            e.fields.begin(), e.fields.end());
        std::sort(ordered_fields.begin(), ordered_fields.end(),
                  [](const auto& a, const auto& b) {
                      const int ra = field_rank_of(a.first);
                      const int rb = field_rank_of(b.first);
                      if (ra != rb) return ra < rb;
                      return to_lower_copy(a.first) < to_lower_copy(b.first);
                  });

        for (const auto& f : ordered_fields) {
            if (should_suppress_field(f.first, f.second)) continue;
            std::string field_l = to_lower_copy(f.first);
            std::cout << ",\n";
            print_wrapped_field(field_l, f.second);
        }
        std::cout << "\n}\n";
    }
    return 0;
}
