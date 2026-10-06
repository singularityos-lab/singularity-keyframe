namespace Singularity.Apps.Keyframe {

    public errordomain ExprError {
        SYNTAX,
        RUNTIME,
        LIMIT
    }

    public enum JsKind {
        UNDEFINED,
        NULL,
        BOOL,
        NUMBER,
        STRING,
        ARRAY,
        OBJECT,
        FUNCTION
    }

    public delegate JsValue JsNative (Interpreter it, JsValue self, JsValue[] args) throws ExprError;
    public delegate JsValue? JsGetter (string name) throws ExprError;
    public delegate bool JsSetter (string name, JsValue v) throws ExprError;
    public delegate JsValue JsValueOf () throws ExprError;
    public delegate JsValue? JsFallback (string name) throws ExprError;

    public class JsValue {
        public JsKind kind = JsKind.UNDEFINED;
        public double num = 0;
        public bool b = false;
        public string str = "";
        public Gee.ArrayList<JsValue>? arr = null;
        public JsObject? obj = null;
        public JsFunction? fn = null;

        public static JsValue undefined () {
            return new JsValue ();
        }

        public static JsValue null_value () {
            var v = new JsValue ();
            v.kind = JsKind.NULL;
            return v;
        }

        public static JsValue boolean (bool b) {
            var v = new JsValue ();
            v.kind = JsKind.BOOL;
            v.b = b;
            return v;
        }

        public static JsValue number (double n) {
            var v = new JsValue ();
            v.kind = JsKind.NUMBER;
            v.num = n;
            return v;
        }

        public static JsValue string_value (string s) {
            var v = new JsValue ();
            v.kind = JsKind.STRING;
            v.str = s;
            return v;
        }

        public static JsValue array (Gee.ArrayList<JsValue> items) {
            var v = new JsValue ();
            v.kind = JsKind.ARRAY;
            v.arr = items;
            return v;
        }

        public static JsValue new_array () {
            return array (new Gee.ArrayList<JsValue> ());
        }

        public static JsValue from_doubles (double[] d) {
            var l = new Gee.ArrayList<JsValue> ();
            foreach (var x in d) l.add (number (x));
            return array (l);
        }

        public static JsValue from_value (double[] d) {
            if (d.length == 1) return number (d[0]);
            return from_doubles (d);
        }

        public static JsValue object (JsObject o) {
            var v = new JsValue ();
            v.kind = JsKind.OBJECT;
            v.obj = o;
            return v;
        }

        public static JsValue function (JsFunction f) {
            var v = new JsValue ();
            v.kind = JsKind.FUNCTION;
            v.fn = f;
            return v;
        }

        public static JsValue native (string name, owned JsNative n) {
            var f = new JsFunction ();
            f.name = name;
            f.native = (owned) n;
            return function (f);
        }

        public bool is_nullish () {
            return kind == JsKind.UNDEFINED || kind == JsKind.NULL;
        }

        public bool is_callable () {
            return kind == JsKind.FUNCTION || (kind == JsKind.OBJECT && obj.call != null);
        }
    }

    public class JsObject {
        public Gee.HashMap<string, JsValue> props = new Gee.HashMap<string, JsValue> ();
        public Gee.ArrayList<string> order = new Gee.ArrayList<string> ();
        public JsGetter? getter = null;
        public JsSetter? setter = null;
        public JsNative? call = null;
        public JsValueOf? value_of = null;
        public string class_name = "Object";
        public Object? host = null;

        public JsValue? own (string name) {
            return props.has_key (name) ? props[name] : null;
        }

        public void put (string name, JsValue v) {
            if (!props.has_key (name)) order.add (name);
            props[name] = v;
        }

        public void remove (string name) {
            props.unset (name);
            order.remove (name);
        }
    }

    public class Env {
        public Gee.HashMap<string, JsValue> vars = new Gee.HashMap<string, JsValue> ();
        public Env? parent;

        public Env (Env? parent = null) {
            this.parent = parent;
        }

        public Env? find (string name) {
            Env? e = this;
            while (e != null) {
                if (e.vars.has_key (name)) return e;
                e = e.parent;
            }
            return null;
        }

        public void define (string name, JsValue v) {
            vars[name] = v;
        }
    }

    public class JsFunction {
        public string name = "";
        public Gee.ArrayList<string> params = new Gee.ArrayList<string> ();
        public Gee.ArrayList<Node?> defaults = new Gee.ArrayList<Node?> ();
        public Node? body = null;
        public bool expr_body = false;
        public bool arrow = false;
        public Env? closure = null;
        public JsValue? bound_this = null;
        public JsNative? native = null;
        public JsObject statics = new JsObject ();
    }

    public enum NK {
        PROGRAM,
        NUM,
        STR,
        TEMPLATE,
        IDENT,
        THIS,
        ARRAY,
        OBJECT,
        FUNC,
        UNARY,
        BINARY,
        LOGICAL,
        ASSIGN,
        UPDATE,
        COND,
        CALL,
        NEW,
        MEMBER,
        INDEX,
        SEQ,
        SPREAD,
        VAR,
        EXPR,
        IF,
        FOR,
        FOROF,
        FORIN,
        WHILE,
        DOWHILE,
        BLOCK,
        RETURN,
        BREAK,
        CONTINUE,
        SWITCH,
        CASE,
        TRY,
        THROW,
        EMPTY,
        BOOL_LIT,
        NULL_LIT,
        UNDEF_LIT
    }

    public class Node {
        public NK kind;
        public string op = "";
        public double num = 0;
        public string str = "";
        public Node? a = null;
        public Node? b = null;
        public Node? c = null;
        public Node? d = null;
        public Gee.ArrayList<Node?> list = new Gee.ArrayList<Node?> ();
        public Gee.ArrayList<string> names = new Gee.ArrayList<string> ();
        public bool flag = false;
        public int line = 1;

        public Node (NK kind, int line = 1) {
            this.kind = kind;
            this.line = line;
        }
    }

    public enum TK {
        NUM,
        STR,
        TEMPLATE,
        IDENT,
        PUNCT,
        EOF
    }

    public class Token {
        public TK kind;
        public string text;
        public double num;
        public int line;
        public bool nl_before;

        public Token (TK kind, string text, int line) {
            this.kind = kind;
            this.text = text;
            this.line = line;
        }
    }

    public class Lexer {
        private string src;
        private int pos = 0;
        private int line = 1;

        private const string[] PUNCTS = {
            ">>>=", "...", "===", "!==", "**=", ">>>", "<<=", ">>=", "&&=", "||=", "??=",
            "=>", "==", "!=", "<=", ">=", "&&", "||", "??", "++", "--", "+=", "-=", "*=", "/=", "%=", "**", "<<", ">>", "&=", "|=", "^=", "?.",
            "{", "}", "(", ")", "[", "]", ";", ",", "<", ">", "+", "-", "*", "/", "%", "&", "|", "^", "!", "~", "?", ":", "=", "."
        };

        public Lexer (string src) {
            this.src = src;
        }

        private char peek (int o = 0) {
            return pos + o < src.length ? src[pos + o] : '\0';
        }

        public Gee.ArrayList<Token> tokenize () throws ExprError {
            var r = new Gee.ArrayList<Token> ();
            bool nl = false;
            while (true) {
                char c = peek ();
                if (c == '\0') break;
                if (c == '\n') {
                    line++;
                    nl = true;
                    pos++;
                    continue;
                }
                if (c == ' ' || c == '\t' || c == '\r') {
                    pos++;
                    continue;
                }
                if (c == '/' && peek (1) == '/') {
                    while (peek () != '\n' && peek () != '\0') pos++;
                    continue;
                }
                if (c == '/' && peek (1) == '*') {
                    pos += 2;
                    while (peek () != '\0' && !(peek () == '*' && peek (1) == '/')) {
                        if (peek () == '\n') line++;
                        pos++;
                    }
                    pos += 2;
                    continue;
                }
                Token t;
                if (c.isdigit () || (c == '.' && peek (1).isdigit ())) {
                    t = number ();
                } else if (c == '"' || c == '\'') {
                    t = string_token (c);
                } else if (c == '`') {
                    t = template ();
                } else if (c.isalpha () || c == '_' || c == '$' || (uchar) c >= 0x80) {
                    int start = pos;
                    while (peek ().isalnum () || peek () == '_' || peek () == '$' || (uchar) peek () >= 0x80) pos++;
                    t = new Token (TK.IDENT, src.substring (start, pos - start), line);
                } else {
                    string? found = null;
                    foreach (var p in PUNCTS) {
                        if (src.substring (pos).has_prefix (p)) {
                            found = p;
                            break;
                        }
                    }
                    if (found == null) throw new ExprError.SYNTAX ("Unexpected character '%c' on line %d", c, line);
                    pos += found.length;
                    t = new Token (TK.PUNCT, found, line);
                }
                t.nl_before = nl;
                nl = false;
                r.add (t);
            }
            var eof = new Token (TK.EOF, "", line);
            eof.nl_before = true;
            r.add (eof);
            return r;
        }

        private Token number () throws ExprError {
            int start = pos;
            double v;
            if (peek () == '0' && (peek (1) == 'x' || peek (1) == 'X')) {
                pos += 2;
                while (peek ().isxdigit ()) pos++;
                int64 n = 0;
                string hex = src.substring (start + 2, pos - start - 2);
                for (int i = 0; i < hex.length; i++) n = n * 16 + hex[i].xdigit_value ();
                v = n;
            } else {
                while (peek ().isdigit ()) pos++;
                if (peek () == '.') {
                    pos++;
                    while (peek ().isdigit ()) pos++;
                }
                if (peek () == 'e' || peek () == 'E') {
                    int save = pos;
                    pos++;
                    if (peek () == '+' || peek () == '-') pos++;
                    if (!peek ().isdigit ()) pos = save;
                    else while (peek ().isdigit ()) pos++;
                }
                v = double.parse (src.substring (start, pos - start));
            }
            var t = new Token (TK.NUM, src.substring (start, pos - start), line);
            t.num = v;
            return t;
        }

        private Token string_token (char q) throws ExprError {
            pos++;
            var sb = new StringBuilder ();
            while (true) {
                char c = peek ();
                if (c == '\0' || c == '\n') throw new ExprError.SYNTAX ("Unterminated string on line %d", line);
                pos++;
                if (c == q) break;
                if (c == '\\') {
                    char e = peek ();
                    pos++;
                    switch (e) {
                        case 'n': sb.append_c ('\n'); break;
                        case 't': sb.append_c ('\t'); break;
                        case 'r': sb.append_c ('\r'); break;
                        case '0': sb.append_c ('\0'); break;
                        case 'u':
                            string hex = src.substring (pos, int.min (4, src.length - pos));
                            int code = 0;
                            for (int i = 0; i < hex.length; i++) code = code * 16 + hex[i].xdigit_value ();
                            sb.append_unichar ((unichar) code);
                            pos += hex.length;
                            break;
                        case '\n':
                            line++;
                            break;
                        default: sb.append_c (e); break;
                    }
                    continue;
                }
                sb.append_c (c);
            }
            return new Token (TK.STR, sb.str, line);
        }

        private Token template () throws ExprError {
            pos++;
            int start = pos;
            int depth = 0;
            while (true) {
                char c = peek ();
                if (c == '\0') throw new ExprError.SYNTAX ("Unterminated template on line %d", line);
                if (c == '\\') {
                    pos += 2;
                    continue;
                }
                if (c == '$' && peek (1) == '{') {
                    depth++;
                    pos += 2;
                    continue;
                }
                if (c == '}' && depth > 0) depth--;
                if (c == '`' && depth == 0) break;
                if (c == '\n') line++;
                pos++;
            }
            var t = new Token (TK.TEMPLATE, src.substring (start, pos - start), line);
            pos++;
            return t;
        }
    }

    public class Parser {
        private Gee.ArrayList<Token> toks;
        private int p = 0;

        public Parser (string src) throws ExprError {
            toks = new Lexer (src).tokenize ();
        }

        public static Node parse_program (string src) throws ExprError {
            var parser = new Parser (src);
            var prog = new Node (NK.PROGRAM);
            while (parser.cur ().kind != TK.EOF) prog.list.add (parser.statement ());
            return prog;
        }

        private Token cur () {
            return toks[p];
        }

        private Token peek_tok (int o) {
            return toks[int.min (p + o, toks.size - 1)];
        }

        private bool is (string text) {
            var t = cur ();
            return (t.kind == TK.PUNCT || t.kind == TK.IDENT) && t.text == text;
        }

        private bool eat (string text) {
            if (is (text)) {
                p++;
                return true;
            }
            return false;
        }

        private void expect (string text) throws ExprError {
            if (!eat (text)) throw new ExprError.SYNTAX ("Expected '%s' but found '%s' on line %d", text, cur ().text, cur ().line);
        }

        private string ident () throws ExprError {
            var t = cur ();
            if (t.kind != TK.IDENT) throw new ExprError.SYNTAX ("Expected a name but found '%s' on line %d", t.text, t.line);
            p++;
            return t.text;
        }

        private void end_statement () {
            if (eat (";")) return;
        }

        public Node statement () throws ExprError {
            var t = cur ();
            int ln = t.line;
            if (t.kind == TK.PUNCT) {
                if (t.text == "{") return block ();
                if (t.text == ";") {
                    p++;
                    return new Node (NK.EMPTY, ln);
                }
            }
            if (t.kind == TK.IDENT) {
                switch (t.text) {
                    case "var":
                    case "let":
                    case "const":
                        var n = var_decl ();
                        end_statement ();
                        return n;
                    case "function":
                        if (peek_tok (1).kind == TK.IDENT) {
                            p++;
                            var f = function_rest (ln);
                            f.flag = true;
                            return f;
                        }
                        break;
                    case "if":
                        p++;
                        expect ("(");
                        var n = new Node (NK.IF, ln);
                        n.a = expression ();
                        expect (")");
                        n.b = statement ();
                        if (eat ("else")) n.c = statement ();
                        return n;
                    case "while":
                        p++;
                        expect ("(");
                        var n = new Node (NK.WHILE, ln);
                        n.a = expression ();
                        expect (")");
                        n.b = statement ();
                        return n;
                    case "do":
                        p++;
                        var n = new Node (NK.DOWHILE, ln);
                        n.b = statement ();
                        expect ("while");
                        expect ("(");
                        n.a = expression ();
                        expect (")");
                        end_statement ();
                        return n;
                    case "for":
                        return for_statement ();
                    case "return":
                        p++;
                        var n = new Node (NK.RETURN, ln);
                        if (!is (";") && !is ("}") && !cur ().nl_before && cur ().kind != TK.EOF) n.a = expression ();
                        end_statement ();
                        return n;
                    case "break":
                        p++;
                        end_statement ();
                        return new Node (NK.BREAK, ln);
                    case "continue":
                        p++;
                        end_statement ();
                        return new Node (NK.CONTINUE, ln);
                    case "throw":
                        p++;
                        var n = new Node (NK.THROW, ln);
                        n.a = expression ();
                        end_statement ();
                        return n;
                    case "switch":
                        return switch_statement ();
                    case "try":
                        p++;
                        var n = new Node (NK.TRY, ln);
                        n.a = block ();
                        if (eat ("catch")) {
                            if (eat ("(")) {
                                n.str = ident ();
                                expect (")");
                            }
                            n.b = block ();
                        }
                        if (eat ("finally")) n.c = block ();
                        return n;
                }
            }
            var e = new Node (NK.EXPR, ln);
            e.a = expression ();
            end_statement ();
            return e;
        }

        private Node block () throws ExprError {
            var n = new Node (NK.BLOCK, cur ().line);
            expect ("{");
            while (!is ("}")) {
                if (cur ().kind == TK.EOF) throw new ExprError.SYNTAX ("Missing '}'");
                n.list.add (statement ());
            }
            expect ("}");
            return n;
        }

        private Node var_decl () throws ExprError {
            var n = new Node (NK.VAR, cur ().line);
            n.op = cur ().text;
            p++;
            do {
                n.names.add (ident ());
                n.list.add (eat ("=") ? assignment () : null);
            } while (eat (","));
            return n;
        }

        private Node for_statement () throws ExprError {
            int ln = cur ().line;
            p++;
            expect ("(");
            Node? init = null;
            if (is ("var") || is ("let") || is ("const")) {
                string kind = cur ().text;
                if (peek_tok (1).kind == TK.IDENT && (peek_tok (2).text == "of" || peek_tok (2).text == "in")) {
                    p++;
                    string name = ident ();
                    bool of = cur ().text == "of";
                    p++;
                    var n = new Node (of ? NK.FOROF : NK.FORIN, ln);
                    n.str = name;
                    n.op = kind;
                    n.a = expression ();
                    expect (")");
                    n.b = statement ();
                    return n;
                }
                init = var_decl ();
            } else if (!is (";")) {
                if (cur ().kind == TK.IDENT && (peek_tok (1).text == "of" || peek_tok (1).text == "in")) {
                    string name = ident ();
                    bool of = cur ().text == "of";
                    p++;
                    var n = new Node (of ? NK.FOROF : NK.FORIN, ln);
                    n.str = name;
                    n.a = expression ();
                    expect (")");
                    n.b = statement ();
                    return n;
                }
                var e = new Node (NK.EXPR, ln);
                e.a = expression ();
                init = e;
            }
            expect (";");
            var n = new Node (NK.FOR, ln);
            n.a = init;
            n.b = is (";") ? null : expression ();
            expect (";");
            n.c = is (")") ? null : expression ();
            expect (")");
            n.d = statement ();
            return n;
        }

        private Node switch_statement () throws ExprError {
            var n = new Node (NK.SWITCH, cur ().line);
            p++;
            expect ("(");
            n.a = expression ();
            expect (")");
            expect ("{");
            while (!eat ("}")) {
                var c = new Node (NK.CASE, cur ().line);
                if (eat ("default")) {
                    c.a = null;
                } else {
                    expect ("case");
                    c.a = expression ();
                }
                expect (":");
                while (!is ("case") && !is ("default") && !is ("}")) {
                    if (cur ().kind == TK.EOF) throw new ExprError.SYNTAX ("Missing '}' in switch");
                    c.list.add (statement ());
                }
                n.list.add (c);
            }
            return n;
        }

        private Node function_rest (int ln) throws ExprError {
            var f = new Node (NK.FUNC, ln);
            if (cur ().kind == TK.IDENT) f.str = ident ();
            expect ("(");
            params (f);
            f.a = block ();
            return f;
        }

        private void params (Node f) throws ExprError {
            while (!eat (")")) {
                if (eat ("...")) f.op = "rest";
                f.names.add (ident ());
                f.list.add (eat ("=") ? assignment () : null);
                if (!is (")")) expect (",");
            }
        }

        public Node expression () throws ExprError {
            var e = assignment ();
            if (is (",")) {
                var seq = new Node (NK.SEQ, e.line);
                seq.list.add (e);
                while (eat (",")) seq.list.add (assignment ());
                return seq;
            }
            return e;
        }

        private bool arrow_ahead () {
            if (cur ().kind == TK.IDENT && peek_tok (1).text == "=>") return true;
            if (!is ("(")) return false;
            int depth = 0;
            for (int i = p; i < toks.size; i++) {
                var t = toks[i];
                if (t.kind == TK.PUNCT && (t.text == "(" || t.text == "[" || t.text == "{")) depth++;
                else if (t.kind == TK.PUNCT && (t.text == ")" || t.text == "]" || t.text == "}")) {
                    depth--;
                    if (depth == 0) return i + 1 < toks.size && toks[i + 1].text == "=>";
                }
            }
            return false;
        }

        private Node arrow () throws ExprError {
            var f = new Node (NK.FUNC, cur ().line);
            f.flag = false;
            f.op = "";
            f.str = "";
            if (cur ().kind == TK.IDENT) {
                f.names.add (ident ());
                f.list.add (null);
            } else {
                expect ("(");
                params (f);
            }
            expect ("=>");
            f.num = 1;
            if (is ("{")) {
                f.a = block ();
            } else {
                var body = new Node (NK.RETURN, cur ().line);
                body.a = assignment ();
                var blk = new Node (NK.BLOCK, body.line);
                blk.list.add (body);
                f.a = blk;
            }
            return f;
        }

        private static bool is_assign_op (string s) {
            switch (s) {
                case "=": case "+=": case "-=": case "*=": case "/=": case "%=": case "**=":
                case "<<=": case ">>=": case ">>>=": case "&=": case "|=": case "^=":
                case "&&=": case "||=": case "??=":
                    return true;
                default:
                    return false;
            }
        }

        private Node assignment () throws ExprError {
            if (arrow_ahead ()) return arrow ();
            var left = conditional ();
            var t = cur ();
            if (t.kind == TK.PUNCT && is_assign_op (t.text)) {
                if (left.kind != NK.IDENT && left.kind != NK.MEMBER && left.kind != NK.INDEX) throw new ExprError.SYNTAX ("Invalid assignment target on line %d", t.line);
                p++;
                var n = new Node (NK.ASSIGN, t.line);
                n.op = t.text;
                n.a = left;
                n.b = assignment ();
                return n;
            }
            return left;
        }

        private Node conditional () throws ExprError {
            var c = binary (0);
            if (eat ("?")) {
                var n = new Node (NK.COND, c.line);
                n.a = c;
                n.b = assignment ();
                expect (":");
                n.c = assignment ();
                return n;
            }
            return c;
        }

        private static int precedence (Token t, out bool right) {
            right = false;
            if (t.kind == TK.IDENT) {
                if (t.text == "in" || t.text == "instanceof") return 11;
                return -1;
            }
            if (t.kind != TK.PUNCT) return -1;
            switch (t.text) {
                case "??": return 4;
                case "||": return 5;
                case "&&": return 6;
                case "|": return 7;
                case "^": return 8;
                case "&": return 9;
                case "==": case "!=": case "===": case "!==": return 10;
                case "<": case ">": case "<=": case ">=": return 11;
                case "<<": case ">>": case ">>>": return 12;
                case "+": case "-": return 13;
                case "*": case "/": case "%": return 14;
                case "**":
                    right = true;
                    return 15;
                default: return -1;
            }
        }

        private Node binary (int min) throws ExprError {
            var left = unary ();
            while (true) {
                var t = cur ();
                bool right;
                int prec = precedence (t, out right);
                if (prec < 0 || prec < min) break;
                p++;
                var rhs = binary (right ? prec : prec + 1);
                var n = new Node ((t.text == "&&" || t.text == "||" || t.text == "??") ? NK.LOGICAL : NK.BINARY, t.line);
                n.op = t.text;
                n.a = left;
                n.b = rhs;
                left = n;
            }
            return left;
        }

        private Node unary () throws ExprError {
            var t = cur ();
            if ((t.kind == TK.PUNCT && (t.text == "!" || t.text == "-" || t.text == "+" || t.text == "~"))
                || (t.kind == TK.IDENT && (t.text == "typeof" || t.text == "void" || t.text == "delete"))) {
                p++;
                var n = new Node (NK.UNARY, t.line);
                n.op = t.text;
                n.a = unary ();
                return n;
            }
            if (t.kind == TK.PUNCT && (t.text == "++" || t.text == "--")) {
                p++;
                var n = new Node (NK.UPDATE, t.line);
                n.op = t.text;
                n.flag = true;
                n.a = unary ();
                return n;
            }
            var e = postfix ();
            return e;
        }

        private Node postfix () throws ExprError {
            var e = call_member ();
            var t = cur ();
            if (t.kind == TK.PUNCT && (t.text == "++" || t.text == "--") && !t.nl_before) {
                p++;
                var n = new Node (NK.UPDATE, t.line);
                n.op = t.text;
                n.flag = false;
                n.a = e;
                return n;
            }
            return e;
        }

        private void arguments (Node call) throws ExprError {
            while (!eat (")")) {
                if (eat ("...")) {
                    var s = new Node (NK.SPREAD, cur ().line);
                    s.a = assignment ();
                    call.list.add (s);
                } else {
                    call.list.add (assignment ());
                }
                if (!is (")")) expect (",");
            }
        }

        private Node call_member () throws ExprError {
            Node e;
            if (eat ("new")) {
                var n = new Node (NK.NEW, cur ().line);
                n.a = primary ();
                while (is (".")) {
                    p++;
                    var m = new Node (NK.MEMBER, cur ().line);
                    m.a = n.a;
                    m.str = ident ();
                    n.a = m;
                }
                if (eat ("(")) arguments (n);
                e = n;
            } else {
                e = primary ();
            }
            while (true) {
                if (is (".") || is ("?.")) {
                    bool opt = cur ().text == "?.";
                    p++;
                    if (opt && is ("(")) {
                        p++;
                        var c = new Node (NK.CALL, cur ().line);
                        c.a = e;
                        c.flag = true;
                        arguments (c);
                        e = c;
                        continue;
                    }
                    if (opt && is ("[")) {
                        p++;
                        var ix = new Node (NK.INDEX, cur ().line);
                        ix.a = e;
                        ix.b = expression ();
                        ix.flag = true;
                        expect ("]");
                        e = ix;
                        continue;
                    }
                    var m = new Node (NK.MEMBER, cur ().line);
                    m.a = e;
                    var t = cur ();
                    if (t.kind != TK.IDENT) throw new ExprError.SYNTAX ("Expected a property name on line %d", t.line);
                    p++;
                    m.str = t.text;
                    m.flag = opt;
                    e = m;
                } else if (is ("[")) {
                    p++;
                    var ix = new Node (NK.INDEX, cur ().line);
                    ix.a = e;
                    ix.b = expression ();
                    expect ("]");
                    e = ix;
                } else if (is ("(")) {
                    p++;
                    var c = new Node (NK.CALL, cur ().line);
                    c.a = e;
                    arguments (c);
                    e = c;
                } else if (cur ().kind == TK.TEMPLATE && !cur ().nl_before) {
                    break;
                } else {
                    break;
                }
            }
            return e;
        }

        private Node primary () throws ExprError {
            var t = cur ();
            int ln = t.line;
            switch (t.kind) {
                case TK.NUM:
                    p++;
                    var n = new Node (NK.NUM, ln);
                    n.num = t.num;
                    return n;
                case TK.STR:
                    p++;
                    var s = new Node (NK.STR, ln);
                    s.str = t.text;
                    return s;
                case TK.TEMPLATE:
                    p++;
                    return template_node (t);
                case TK.IDENT:
                    switch (t.text) {
                        case "true":
                        case "false":
                            p++;
                            var bn = new Node (NK.BOOL_LIT, ln);
                            bn.flag = t.text == "true";
                            return bn;
                        case "null":
                            p++;
                            return new Node (NK.NULL_LIT, ln);
                        case "undefined":
                            p++;
                            return new Node (NK.UNDEF_LIT, ln);
                        case "this":
                            p++;
                            return new Node (NK.THIS, ln);
                        case "function":
                            p++;
                            return function_rest (ln);
                    }
                    p++;
                    var id = new Node (NK.IDENT, ln);
                    id.str = t.text;
                    return id;
                case TK.PUNCT:
                    if (t.text == "(") {
                        p++;
                        var e = expression ();
                        expect (")");
                        return e;
                    }
                    if (t.text == "[") {
                        p++;
                        var arr = new Node (NK.ARRAY, ln);
                        while (!eat ("]")) {
                            if (is (",")) {
                                p++;
                                arr.list.add (new Node (NK.UNDEF_LIT, ln));
                                continue;
                            }
                            if (eat ("...")) {
                                var sp = new Node (NK.SPREAD, ln);
                                sp.a = assignment ();
                                arr.list.add (sp);
                            } else {
                                arr.list.add (assignment ());
                            }
                            if (!is ("]")) expect (",");
                        }
                        return arr;
                    }
                    if (t.text == "{") {
                        p++;
                        var obj = new Node (NK.OBJECT, ln);
                        while (!eat ("}")) {
                            var kt = cur ();
                            string key;
                            if (kt.kind == TK.STR || kt.kind == TK.IDENT) key = kt.text;
                            else if (kt.kind == TK.NUM) key = Interpreter.number_to_string (kt.num);
                            else throw new ExprError.SYNTAX ("Bad object key on line %d", kt.line);
                            p++;
                            if (is ("(")) {
                                var f = new Node (NK.FUNC, kt.line);
                                f.str = key;
                                p++;
                                params (f);
                                f.a = block ();
                                obj.names.add (key);
                                obj.list.add (f);
                            } else if (eat (":")) {
                                obj.names.add (key);
                                obj.list.add (assignment ());
                            } else {
                                var id = new Node (NK.IDENT, kt.line);
                                id.str = key;
                                obj.names.add (key);
                                obj.list.add (id);
                            }
                            if (!is ("}")) expect (",");
                        }
                        return obj;
                    }
                    break;
                default:
                    break;
            }
            throw new ExprError.SYNTAX ("Unexpected '%s' on line %d", t.kind == TK.EOF ? "end of input" : t.text, t.line);
        }

        private Node template_node (Token t) throws ExprError {
            var n = new Node (NK.TEMPLATE, t.line);
            string s = t.text;
            var lit = new StringBuilder ();
            int i = 0;
            while (i < s.length) {
                char c = s[i];
                if (c == '\\' && i + 1 < s.length) {
                    char e = s[i + 1];
                    lit.append_c (e == 'n' ? '\n' : (e == 't' ? '\t' : e));
                    i += 2;
                    continue;
                }
                if (c == '$' && i + 1 < s.length && s[i + 1] == '{') {
                    var ln = new Node (NK.STR, t.line);
                    ln.str = lit.str;
                    n.list.add (ln);
                    lit.truncate (0);
                    int depth = 1, j = i + 2;
                    while (j < s.length && depth > 0) {
                        if (s[j] == '{') depth++;
                        else if (s[j] == '}') depth--;
                        if (depth > 0) j++;
                    }
                    var inner = new Parser (s.substring (i + 2, j - i - 2));
                    n.list.add (inner.expression ());
                    i = j + 1;
                    continue;
                }
                lit.append_c (c);
                i++;
            }
            var last = new Node (NK.STR, t.line);
            last.str = lit.str;
            n.list.add (last);
            return n;
        }
    }

    public enum Completion {
        NORMAL,
        BREAK,
        CONTINUE,
        RETURN
    }

    public class Interpreter {
        public Env globals = new Env ();
        public int step_limit = 2000000;
        public int depth_limit = 200;
        public int steps = 0;
        public int depth = 0;
        public JsValue last_value = JsValue.undefined ();
        public JsFallback? fallback = null;
        private JsValue ret_value = JsValue.undefined ();
        private int fn_depth = 0;
        private Gee.HashMap<string, Node> cache = new Gee.HashMap<string, Node> ();
        private Gee.HashMap<string, string> cache_errors = new Gee.HashMap<string, string> ();
        public Gee.HashMap<string, JsValue> prototypes_string = new Gee.HashMap<string, JsValue> ();
        public uint random_state = 12345;

        public Interpreter () {
            Builtins.install (this);
        }

        public Node compile (string code) throws ExprError {
            if (cache.has_key (code)) return cache[code];
            if (cache_errors.has_key (code)) throw new ExprError.SYNTAX ("%s", cache_errors[code]);
            try {
                var n = Parser.parse_program (code);
                if (cache.size > 512) cache.clear ();
                cache[code] = n;
                return n;
            } catch (ExprError e) {
                if (cache_errors.size > 512) cache_errors.clear ();
                cache_errors[code] = e.message;
                throw e;
            }
        }

        public JsValue run (string code, Env? scope = null) throws ExprError {
            var prog = compile (code);
            return run_node (prog, scope ?? new Env (globals));
        }

        public JsValue run_node (Node prog, Env env) throws ExprError {
            steps = 0;
            depth = 0;
            fn_depth = 0;
            last_value = JsValue.undefined ();
            hoist (prog.list, env);
            foreach (var s in prog.list) {
                var c = exec (s, env);
                if (c == Completion.RETURN) return ret_value;
                if (c != Completion.NORMAL) break;
            }
            return last_value;
        }

        private void tick () throws ExprError {
            if (++steps > step_limit) throw new ExprError.LIMIT ("The expression took too many steps");
        }

        private void hoist (Gee.List<Node?> stmts, Env env) throws ExprError {
            foreach (var s in stmts) {
                if (s != null && s.kind == NK.FUNC && s.flag && s.str != "") env.define (s.str, make_function (s, env));
            }
        }

        private JsValue make_function (Node n, Env env) {
            var f = new JsFunction ();
            f.name = n.str;
            foreach (var nm in n.names) f.params.add (nm);
            foreach (var d in n.list) f.defaults.add (d);
            f.body = n.a;
            f.arrow = n.num == 1;
            f.closure = env;
            if (n.op == "rest") f.name = f.name;
            var v = JsValue.function (f);
            if (n.op == "rest") f.statics.put ("__rest", JsValue.boolean (true));
            return v;
        }

        public Completion exec (Node s, Env env) throws ExprError {
            tick ();
            switch (s.kind) {
                case NK.EMPTY:
                    return Completion.NORMAL;
                case NK.EXPR:
                    var v = eval (s.a, env);
                    if (fn_depth == 0) last_value = v;
                    return Completion.NORMAL;
                case NK.VAR:
                    for (int i = 0; i < s.names.size; i++) {
                        var init = s.list[i];
                        env.define (s.names[i], init != null ? eval (init, env) : JsValue.undefined ());
                    }
                    return Completion.NORMAL;
                case NK.FUNC:
                    if (s.flag) {
                        if (!env.vars.has_key (s.str)) env.define (s.str, make_function (s, env));
                        return Completion.NORMAL;
                    }
                    var fv = eval (s, env);
                    if (fn_depth == 0) last_value = fv;
                    return Completion.NORMAL;
                case NK.BLOCK:
                    var inner = new Env (env);
                    hoist (s.list, inner);
                    foreach (var st in s.list) {
                        var c = exec (st, inner);
                        if (c != Completion.NORMAL) return c;
                    }
                    return Completion.NORMAL;
                case NK.IF:
                    if (truthy (eval (s.a, env))) return exec (s.b, env);
                    if (s.c != null) return exec (s.c, env);
                    return Completion.NORMAL;
                case NK.WHILE:
                    while (truthy (eval (s.a, env))) {
                        var c = exec (s.b, env);
                        if (c == Completion.BREAK) break;
                        if (c == Completion.RETURN) return c;
                    }
                    return Completion.NORMAL;
                case NK.DOWHILE:
                    do {
                        var c = exec (s.b, env);
                        if (c == Completion.BREAK) break;
                        if (c == Completion.RETURN) return c;
                    } while (truthy (eval (s.a, env)));
                    return Completion.NORMAL;
                case NK.FOR:
                    var fenv = new Env (env);
                    if (s.a != null) exec (s.a, fenv);
                    while (s.b == null || truthy (eval (s.b, fenv))) {
                        var c = exec (s.d, fenv);
                        if (c == Completion.BREAK) break;
                        if (c == Completion.RETURN) return c;
                        if (s.c != null) eval (s.c, fenv);
                    }
                    return Completion.NORMAL;
                case NK.FOROF:
                case NK.FORIN:
                    var coll = eval (s.a, env);
                    var items = new Gee.ArrayList<JsValue> ();
                    if (s.kind == NK.FOROF) {
                        if (coll.kind == JsKind.ARRAY) items.add_all (coll.arr);
                        else if (coll.kind == JsKind.STRING) {
                            int idx = 0;
                            unichar ch;
                            while (coll.str.get_next_char (ref idx, out ch)) items.add (JsValue.string_value (ch.to_string ()));
                        } else throw new ExprError.RUNTIME ("Value is not iterable");
                    } else {
                        if (coll.kind == JsKind.ARRAY) for (int i = 0; i < coll.arr.size; i++) items.add (JsValue.string_value (i.to_string ()));
                        else if (coll.kind == JsKind.OBJECT) foreach (var k in coll.obj.order) items.add (JsValue.string_value (k));
                    }
                    foreach (var it in items) {
                        var le = new Env (env);
                        if (s.op != "") le.define (s.str, it);
                        else assign_name (s.str, it, env);
                        var c = exec (s.b, le);
                        if (c == Completion.BREAK) break;
                        if (c == Completion.RETURN) return c;
                    }
                    return Completion.NORMAL;
                case NK.RETURN:
                    ret_value = s.a != null ? eval (s.a, env) : JsValue.undefined ();
                    if (fn_depth == 0) last_value = ret_value;
                    return Completion.RETURN;
                case NK.BREAK:
                    return Completion.BREAK;
                case NK.CONTINUE:
                    return Completion.CONTINUE;
                case NK.THROW:
                    var tv = eval (s.a, env);
                    throw new ExprError.RUNTIME ("%s", to_string (tv));
                case NK.TRY:
                    Completion result = Completion.NORMAL;
                    try {
                        result = exec (s.a, env);
                    } catch (ExprError e) {
                        if (e is ExprError.LIMIT || s.b == null) {
                            if (s.c != null) exec (s.c, env);
                            throw e;
                        }
                        var cenv = new Env (env);
                        if (s.str != "") cenv.define (s.str, JsValue.string_value (e.message));
                        result = exec (s.b, cenv);
                    }
                    if (s.c != null) {
                        var fc = exec (s.c, env);
                        if (fc != Completion.NORMAL) return fc;
                    }
                    return result;
                case NK.SWITCH:
                    var disc = eval (s.a, env);
                    int start = -1;
                    for (int i = 0; i < s.list.size; i++) {
                        var cs = s.list[i];
                        if (cs.a != null && strict_equals (disc, eval (cs.a, env))) {
                            start = i;
                            break;
                        }
                    }
                    if (start < 0) for (int i = 0; i < s.list.size; i++) if (s.list[i].a == null) start = i;
                    if (start < 0) return Completion.NORMAL;
                    var senv = new Env (env);
                    for (int i = start; i < s.list.size; i++) {
                        foreach (var st in s.list[i].list) {
                            var c = exec (st, senv);
                            if (c == Completion.BREAK) return Completion.NORMAL;
                            if (c != Completion.NORMAL) return c;
                        }
                    }
                    return Completion.NORMAL;
                default:
                    var dv = eval (s, env);
                    if (fn_depth == 0) last_value = dv;
                    return Completion.NORMAL;
            }
        }

        public void assign_name (string name, JsValue v, Env env) {
            var e = env.find (name);
            if (e != null) e.vars[name] = v;
            else globals.define (name, v);
        }

        public JsValue lookup (string name, Env env) throws ExprError {
            var e = env.find (name);
            if (e != null) return e.vars[name];
            if (fallback != null) {
                var r = fallback (name);
                if (r != null) return r;
            }
            throw new ExprError.RUNTIME ("%s is not defined", name);
        }

        public JsValue eval (Node n, Env env) throws ExprError {
            tick ();
            switch (n.kind) {
                case NK.NUM:
                    return JsValue.number (n.num);
                case NK.STR:
                    return JsValue.string_value (n.str);
                case NK.BOOL_LIT:
                    return JsValue.boolean (n.flag);
                case NK.NULL_LIT:
                    return JsValue.null_value ();
                case NK.UNDEF_LIT:
                    return JsValue.undefined ();
                case NK.TEMPLATE:
                    var sb = new StringBuilder ();
                    foreach (var part in n.list) sb.append (to_string (eval (part, env)));
                    return JsValue.string_value (sb.str);
                case NK.IDENT:
                    return lookup (n.str, env);
                case NK.THIS:
                    var te = env.find ("this");
                    return te != null ? te.vars["this"] : JsValue.undefined ();
                case NK.ARRAY:
                    var items = new Gee.ArrayList<JsValue> ();
                    foreach (var e in n.list) {
                        if (e.kind == NK.SPREAD) {
                            var sv = eval (e.a, env);
                            if (sv.kind == JsKind.ARRAY) items.add_all (sv.arr);
                            else throw new ExprError.RUNTIME ("Spread of a non array");
                        } else {
                            items.add (prim (eval (e, env)));
                        }
                    }
                    return JsValue.array (items);
                case NK.OBJECT:
                    var o = new JsObject ();
                    for (int i = 0; i < n.names.size; i++) o.put (n.names[i], eval (n.list[i], env));
                    return JsValue.object (o);
                case NK.FUNC:
                    var fv = make_function (n, env);
                    if (n.str != "" && !n.flag) {
                        var named = new Env (env);
                        named.define (n.str, fv);
                        fv.fn.closure = named;
                    }
                    return fv;
                case NK.UNARY:
                    return unary (n, env);
                case NK.BINARY:
                    return binary (n.op, eval (n.a, env), eval (n.b, env));
                case NK.LOGICAL:
                    var l = eval (n.a, env);
                    if (n.op == "&&") return truthy (l) ? eval (n.b, env) : l;
                    if (n.op == "||") return truthy (l) ? l : eval (n.b, env);
                    return l.is_nullish () ? eval (n.b, env) : l;
                case NK.COND:
                    return truthy (eval (n.a, env)) ? eval (n.b, env) : eval (n.c, env);
                case NK.ASSIGN:
                    return assign (n, env);
                case NK.UPDATE:
                    var old = to_number (eval (n.a, env));
                    var nv = JsValue.number (n.op == "++" ? old + 1 : old - 1);
                    store (n.a, nv, env);
                    return n.flag ? nv : JsValue.number (old);
                case NK.SEQ:
                    JsValue last = JsValue.undefined ();
                    foreach (var e in n.list) last = eval (e, env);
                    return last;
                case NK.MEMBER:
                    var ov = eval (n.a, env);
                    if (n.flag && ov.is_nullish ()) return JsValue.undefined ();
                    return get_member (ov, n.str);
                case NK.INDEX:
                    var iv = eval (n.a, env);
                    if (n.flag && iv.is_nullish ()) return JsValue.undefined ();
                    return get_index (iv, eval (n.b, env));
                case NK.CALL:
                    return call_node (n, env);
                case NK.NEW:
                    var ctor = eval (n.a, env);
                    var args = eval_args (n.list, env);
                    if (n.a.kind == NK.IDENT && n.a.str == "Array") {
                        var arr = new Gee.ArrayList<JsValue> ();
                        if (args.length == 1 && args[0].kind == JsKind.NUMBER) for (int i = 0; i < (int) args[0].num; i++) arr.add (JsValue.undefined ());
                        else foreach (var a in args) arr.add (a);
                        return JsValue.array (arr);
                    }
                    if (n.a.kind == NK.IDENT && n.a.str == "Object") return JsValue.object (new JsObject ());
                    var self = JsValue.object (new JsObject ());
                    var r = call (ctor, self, args);
                    return r.kind == JsKind.OBJECT || r.kind == JsKind.ARRAY ? r : self;
                case NK.SPREAD:
                    throw new ExprError.SYNTAX ("Unexpected spread");
                default:
                    throw new ExprError.RUNTIME ("Unsupported construct");
            }
        }

        private JsValue[] eval_args (Gee.List<Node?> list, Env env) throws ExprError {
            JsValue[] args = {};
            foreach (var a in list) {
                if (a.kind == NK.SPREAD) {
                    var sv = eval (a.a, env);
                    if (sv.kind == JsKind.ARRAY) foreach (var x in sv.arr) args += x;
                } else {
                    args += eval (a, env);
                }
            }
            return args;
        }

        private JsValue call_node (Node n, Env env) throws ExprError {
            JsValue self = JsValue.undefined ();
            JsValue f;
            if (n.a.kind == NK.MEMBER) {
                self = eval (n.a.a, env);
                if (n.a.flag && self.is_nullish ()) return JsValue.undefined ();
                f = get_member (self, n.a.str);
                if (f.kind == JsKind.UNDEFINED) throw new ExprError.RUNTIME ("%s is not a function", n.a.str);
            } else if (n.a.kind == NK.INDEX) {
                self = eval (n.a.a, env);
                f = get_index (self, eval (n.a.b, env));
            } else {
                f = eval (n.a, env);
            }
            if (n.flag && f.is_nullish ()) return JsValue.undefined ();
            var args = eval_args (n.list, env);
            if (!f.is_callable ()) {
                string what = n.a.kind == NK.IDENT ? n.a.str : (n.a.kind == NK.MEMBER ? n.a.str : "value");
                throw new ExprError.RUNTIME ("%s is not a function", what);
            }
            return call (f, self, args);
        }

        public JsValue call (JsValue f, JsValue self, JsValue[] args) throws ExprError {
            if (f.kind == JsKind.OBJECT && f.obj.call != null) return f.obj.call (this, self, args);
            if (f.kind != JsKind.FUNCTION) throw new ExprError.RUNTIME ("Value is not a function");
            var fn = f.fn;
            if (fn.native != null) return fn.native (this, self, args);
            if (++depth > depth_limit) {
                depth = 0;
                throw new ExprError.LIMIT ("Too much recursion");
            }
            var env = new Env (fn.closure);
            if (!fn.arrow) env.define ("this", fn.bound_this ?? self);
            bool rest = fn.statics.own ("__rest") != null;
            var argl = new Gee.ArrayList<JsValue> ();
            foreach (var a in args) argl.add (a);
            if (!fn.arrow) env.define ("arguments", JsValue.array (argl));
            for (int i = 0; i < fn.params.size; i++) {
                if (rest && i == fn.params.size - 1) {
                    var r = new Gee.ArrayList<JsValue> ();
                    for (int k = i; k < args.length; k++) r.add (args[k]);
                    env.define (fn.params[i], JsValue.array (r));
                    break;
                }
                JsValue v = i < args.length ? args[i] : JsValue.undefined ();
                if (v.kind == JsKind.UNDEFINED && fn.defaults[i] != null) v = eval (fn.defaults[i], env);
                env.define (fn.params[i], v);
            }
            fn_depth++;
            JsValue result = JsValue.undefined ();
            try {
                hoist (fn.body.list, env);
                foreach (var st in fn.body.list) {
                    var c = exec (st, env);
                    if (c == Completion.RETURN) {
                        result = ret_value;
                        break;
                    }
                    if (c != Completion.NORMAL) break;
                }
            } finally {
                fn_depth--;
                depth--;
            }
            return result;
        }

        private JsValue assign (Node n, Env env) throws ExprError {
            JsValue v;
            if (n.op == "=") {
                v = eval (n.b, env);
            } else if (n.op == "&&=" || n.op == "||=" || n.op == "??=") {
                var cur_v = eval (n.a, env);
                bool keep = n.op == "&&=" ? !truthy (cur_v) : (n.op == "||=" ? truthy (cur_v) : !cur_v.is_nullish ());
                if (keep) return cur_v;
                v = eval (n.b, env);
            } else {
                var cur_v = eval (n.a, env);
                v = binary (n.op.substring (0, n.op.length - 1), cur_v, eval (n.b, env));
            }
            store (n.a, v, env);
            return v;
        }

        private void store (Node target, JsValue v, Env env) throws ExprError {
            if (target.kind == NK.IDENT) {
                assign_name (target.str, v, env);
            } else if (target.kind == NK.MEMBER) {
                set_member (eval (target.a, env), target.str, v);
            } else if (target.kind == NK.INDEX) {
                var o = eval (target.a, env);
                var k = eval (target.b, env);
                if (o.kind == JsKind.ARRAY && k.kind == JsKind.NUMBER) {
                    int i = (int) k.num;
                    if (i < 0) throw new ExprError.RUNTIME ("Negative array index");
                    if (i > 1000000) throw new ExprError.LIMIT ("Array too large");
                    while (o.arr.size <= i) o.arr.add (JsValue.undefined ());
                    o.arr[i] = v;
                } else {
                    set_member (o, to_string (k), v);
                }
            } else {
                throw new ExprError.SYNTAX ("Invalid assignment target");
            }
        }

        private JsValue unary (Node n, Env env) throws ExprError {
            if (n.op == "typeof") {
                JsValue v;
                if (n.a.kind == NK.IDENT && env.find (n.a.str) == null) {
                    try {
                        v = lookup (n.a.str, env);
                    } catch (ExprError e) {
                        return JsValue.string_value ("undefined");
                    }
                } else {
                    v = eval (n.a, env);
                }
                return JsValue.string_value (type_of (v));
            }
            if (n.op == "delete") {
                if (n.a.kind == NK.MEMBER) {
                    var o = eval (n.a.a, env);
                    if (o.kind == JsKind.OBJECT) o.obj.remove (n.a.str);
                }
                return JsValue.boolean (true);
            }
            var v = eval (n.a, env);
            switch (n.op) {
                case "!": return JsValue.boolean (!truthy (v));
                case "void": return JsValue.undefined ();
                case "~": return JsValue.number (~to_int32 (v));
                case "+": return JsValue.number (to_number (v));
                default:
                    var pv = prim (v);
                    if (pv.kind == JsKind.ARRAY) {
                        var r = new Gee.ArrayList<JsValue> ();
                        foreach (var x in pv.arr) r.add (JsValue.number (-to_number (x)));
                        return JsValue.array (r);
                    }
                    return JsValue.number (-to_number (pv));
            }
        }

        public static string type_of (JsValue v) {
            switch (v.kind) {
                case JsKind.UNDEFINED: return "undefined";
                case JsKind.NULL: return "object";
                case JsKind.BOOL: return "boolean";
                case JsKind.NUMBER: return "number";
                case JsKind.STRING: return "string";
                case JsKind.FUNCTION: return "function";
                case JsKind.OBJECT: return v.obj.call != null ? "function" : "object";
                default: return "object";
            }
        }

        public JsValue prim (JsValue v) throws ExprError {
            if (v.kind == JsKind.OBJECT && v.obj.value_of != null) return v.obj.value_of ();
            return v;
        }

        private static int32 to_int32 (JsValue v) {
            double d = v.kind == JsKind.NUMBER ? v.num : 0;
            if (d.is_nan () || d.is_infinity () != 0) return 0;
            return (int32) (int64) d;
        }

        private JsValue array_op (string op, JsValue a, JsValue b) throws ExprError {
            var r = new Gee.ArrayList<JsValue> ();
            if (a.kind == JsKind.ARRAY && b.kind == JsKind.ARRAY) {
                int n = int.max (a.arr.size, b.arr.size);
                for (int i = 0; i < n; i++) {
                    double x = i < a.arr.size ? to_number (a.arr[i]) : 0;
                    double y = i < b.arr.size ? to_number (b.arr[i]) : 0;
                    r.add (JsValue.number (arith (op, x, y)));
                }
            } else if (a.kind == JsKind.ARRAY) {
                double y = to_number (b);
                foreach (var x in a.arr) r.add (JsValue.number (arith (op, to_number (x), y)));
            } else {
                double x = to_number (a);
                foreach (var y in b.arr) r.add (JsValue.number (arith (op, x, to_number (y))));
            }
            return JsValue.array (r);
        }

        private static double arith (string op, double x, double y) {
            switch (op) {
                case "+": return x + y;
                case "-": return x - y;
                case "*": return x * y;
                case "/": return x / y;
                case "%": return y == 0 ? double.NAN : Math.fmod (x, y);
                case "**": return Math.pow (x, y);
                default: return double.NAN;
            }
        }

        public JsValue binary (string op, JsValue av, JsValue bv) throws ExprError {
            if (op == "===" || op == "!==") {
                bool eq = strict_equals (prim_for_compare (av), prim_for_compare (bv));
                return JsValue.boolean (op == "===" ? eq : !eq);
            }
            if (op == "==" || op == "!=") {
                bool eq = loose_equals (prim (av), prim (bv));
                return JsValue.boolean (op == "==" ? eq : !eq);
            }
            if (op == "in") {
                var key = to_string (av);
                if (bv.kind == JsKind.OBJECT) return JsValue.boolean (bv.obj.own (key) != null || (bv.obj.getter != null && bv.obj.getter (key) != null));
                if (bv.kind == JsKind.ARRAY) return JsValue.boolean (int.parse (key) < bv.arr.size);
                return JsValue.boolean (false);
            }
            if (op == "instanceof") return JsValue.boolean (false);
            var a = prim (av);
            var b = prim (bv);
            switch (op) {
                case "+":
                    if (a.kind == JsKind.STRING || b.kind == JsKind.STRING) return JsValue.string_value (to_string (a) + to_string (b));
                    if (a.kind == JsKind.ARRAY || b.kind == JsKind.ARRAY) return array_op (op, a, b);
                    return JsValue.number (to_number (a) + to_number (b));
                case "-":
                case "*":
                case "/":
                case "%":
                case "**":
                    if (a.kind == JsKind.ARRAY || b.kind == JsKind.ARRAY) return array_op (op, a, b);
                    return JsValue.number (arith (op, to_number (a), to_number (b)));
                case "<":
                case ">":
                case "<=":
                case ">=":
                    if (a.kind == JsKind.STRING && b.kind == JsKind.STRING) {
                        int c = strcmp (a.str, b.str);
                        return JsValue.boolean (op == "<" ? c < 0 : (op == ">" ? c > 0 : (op == "<=" ? c <= 0 : c >= 0)));
                    }
                    double x = to_number (a), y = to_number (b);
                    if (x.is_nan () || y.is_nan ()) return JsValue.boolean (false);
                    return JsValue.boolean (op == "<" ? x < y : (op == ">" ? x > y : (op == "<=" ? x <= y : x >= y)));
                case "&": return JsValue.number (to_int32 (JsValue.number (to_number (a))) & to_int32 (JsValue.number (to_number (b))));
                case "|": return JsValue.number (to_int32 (JsValue.number (to_number (a))) | to_int32 (JsValue.number (to_number (b))));
                case "^": return JsValue.number (to_int32 (JsValue.number (to_number (a))) ^ to_int32 (JsValue.number (to_number (b))));
                case "<<": return JsValue.number (to_int32 (JsValue.number (to_number (a))) << (to_int32 (JsValue.number (to_number (b))) & 31));
                case ">>": return JsValue.number (to_int32 (JsValue.number (to_number (a))) >> (to_int32 (JsValue.number (to_number (b))) & 31));
                case ">>>": return JsValue.number ((uint32) to_int32 (JsValue.number (to_number (a))) >> (to_int32 (JsValue.number (to_number (b))) & 31));
                default:
                    throw new ExprError.RUNTIME ("Unknown operator %s", op);
            }
        }

        private JsValue prim_for_compare (JsValue v) throws ExprError {
            if (v.kind == JsKind.OBJECT && v.obj.value_of != null && v.obj.host != null) {
                var p = prim (v);
                if (p.kind != JsKind.ARRAY) return p;
            }
            return v;
        }

        public bool strict_equals (JsValue a, JsValue b) {
            if (a.kind != b.kind) return false;
            switch (a.kind) {
                case JsKind.UNDEFINED:
                case JsKind.NULL:
                    return true;
                case JsKind.BOOL: return a.b == b.b;
                case JsKind.NUMBER: return a.num == b.num;
                case JsKind.STRING: return a.str == b.str;
                case JsKind.ARRAY: return a.arr == b.arr;
                case JsKind.OBJECT: return a.obj == b.obj || (a.obj.host != null && a.obj.host == b.obj.host);
                case JsKind.FUNCTION: return a.fn == b.fn;
                default: return false;
            }
        }

        public bool loose_equals (JsValue a, JsValue b) {
            if (a.is_nullish () && b.is_nullish ()) return true;
            if (a.is_nullish () || b.is_nullish ()) return false;
            if (a.kind == b.kind) return strict_equals (a, b);
            if ((a.kind == JsKind.NUMBER || a.kind == JsKind.STRING || a.kind == JsKind.BOOL) && (b.kind == JsKind.NUMBER || b.kind == JsKind.STRING || b.kind == JsKind.BOOL))
                return to_number (a) == to_number (b);
            if (a.kind == JsKind.ARRAY && b.kind != JsKind.OBJECT) return to_string (a) == to_string (b);
            if (b.kind == JsKind.ARRAY && a.kind != JsKind.OBJECT) return to_string (a) == to_string (b);
            return false;
        }

        public bool truthy (JsValue v) {
            switch (v.kind) {
                case JsKind.UNDEFINED:
                case JsKind.NULL:
                    return false;
                case JsKind.BOOL: return v.b;
                case JsKind.NUMBER: return v.num != 0 && !v.num.is_nan ();
                case JsKind.STRING: return v.str != "";
                default: return true;
            }
        }

        public double to_number (JsValue v) {
            switch (v.kind) {
                case JsKind.NUMBER: return v.num;
                case JsKind.BOOL: return v.b ? 1 : 0;
                case JsKind.NULL: return 0;
                case JsKind.STRING:
                    var s = v.str.strip ();
                    if (s == "") return 0;
                    double d;
                    if (double.try_parse (s, out d)) return d;
                    if (s.has_prefix ("0x")) {
                        int64 n = 0;
                        for (int i = 2; i < s.length; i++) {
                            int x = s[i].xdigit_value ();
                            if (x < 0) return double.NAN;
                            n = n * 16 + x;
                        }
                        return n;
                    }
                    if (s == "Infinity") return double.INFINITY;
                    if (s == "-Infinity") return -double.INFINITY;
                    return double.NAN;
                case JsKind.ARRAY:
                    if (v.arr.size == 0) return 0;
                    if (v.arr.size == 1) return to_number (v.arr[0]);
                    return double.NAN;
                case JsKind.OBJECT:
                    if (v.obj.value_of != null) {
                        try {
                            return to_number (v.obj.value_of ());
                        } catch (ExprError e) {
                            return double.NAN;
                        }
                    }
                    return double.NAN;
                default: return double.NAN;
            }
        }

        public static string number_to_string (double d) {
            if (d.is_nan ()) return "NaN";
            if (d.is_infinity () > 0) return "Infinity";
            if (d.is_infinity () < 0) return "-Infinity";
            if (d == 0) return "0";
            if (d == Math.floor (d) && d.abs () < 1e21) return "%.0f".printf (d);
            for (int prec = 1; prec <= 17; prec++) {
                var s = ("%." + prec.to_string () + "g").printf (d);
                if (double.parse (s) == d) return s;
            }
            return "%.17g".printf (d);
        }

        public string to_string (JsValue v) {
            switch (v.kind) {
                case JsKind.UNDEFINED: return "undefined";
                case JsKind.NULL: return "null";
                case JsKind.BOOL: return v.b ? "true" : "false";
                case JsKind.NUMBER: return number_to_string (v.num);
                case JsKind.STRING: return v.str;
                case JsKind.ARRAY:
                    var parts = new string[v.arr.size];
                    for (int i = 0; i < v.arr.size; i++) parts[i] = v.arr[i].is_nullish () ? "" : to_string (v.arr[i]);
                    return string.joinv (",", parts);
                case JsKind.FUNCTION: return "function " + v.fn.name + "() { [code] }";
                default:
                    if (v.obj.value_of != null) {
                        try {
                            return to_string (v.obj.value_of ());
                        } catch (ExprError e) {
                            return "[object Object]";
                        }
                    }
                    return "[object " + v.obj.class_name + "]";
            }
        }

        public JsValue get_index (JsValue o, JsValue k) throws ExprError {
            if (o.kind == JsKind.ARRAY && k.kind == JsKind.NUMBER) {
                int i = (int) k.num;
                return i >= 0 && i < o.arr.size ? o.arr[i] : JsValue.undefined ();
            }
            if (o.kind == JsKind.STRING && k.kind == JsKind.NUMBER) {
                int i = (int) k.num;
                if (i < 0 || i >= o.str.char_count ()) return JsValue.undefined ();
                return JsValue.string_value (o.str.get_char (o.str.index_of_nth_char (i)).to_string ());
            }
            if (o.kind == JsKind.OBJECT && k.kind == JsKind.NUMBER && o.obj.value_of != null && o.obj.own (to_string (k)) == null) {
                var pv = prim (o);
                if (pv.kind == JsKind.ARRAY) return get_index (pv, k);
            }
            return get_member (o, to_string (k));
        }

        public JsValue get_member (JsValue o, string name) throws ExprError {
            switch (o.kind) {
                case JsKind.UNDEFINED:
                case JsKind.NULL:
                    throw new ExprError.RUNTIME ("Cannot read property '%s' of %s", name, o.kind == JsKind.NULL ? "null" : "undefined");
                case JsKind.OBJECT:
                    var own = o.obj.own (name);
                    if (own != null) return own;
                    if (o.obj.getter != null) {
                        var g = o.obj.getter (name);
                        if (g != null) return g;
                    }
                    if (o.obj.value_of != null) {
                        var pv = prim (o);
                        if (pv.kind != JsKind.OBJECT) return get_member (pv, name);
                    }
                    if (name == "hasOwnProperty") {
                        var oo = o.obj;
                        return JsValue.native ("hasOwnProperty", (it, self, args) => JsValue.boolean (args.length > 0 && oo.own (it.to_string (args[0])) != null));
                    }
                    if (name == "toString") return JsValue.native ("toString", (it, self, args) => JsValue.string_value (it.to_string (self)));
                    return JsValue.undefined ();
                case JsKind.FUNCTION:
                    var st = o.fn.statics.own (name);
                    if (st != null) return st;
                    if (name == "name") return JsValue.string_value (o.fn.name);
                    if (name == "length") return JsValue.number (o.fn.params.size);
                    if (name == "call") {
                        var target = o;
                        return JsValue.native ("call", (it, self, args) => {
                            JsValue[] rest = {};
                            for (int i = 1; i < args.length; i++) rest += args[i];
                            return it.call (target, args.length > 0 ? args[0] : JsValue.undefined (), rest);
                        });
                    }
                    if (name == "apply") {
                        var target = o;
                        return JsValue.native ("apply", (it, self, args) => {
                            JsValue[] rest = {};
                            if (args.length > 1 && args[1].kind == JsKind.ARRAY) foreach (var x in args[1].arr) rest += x;
                            return it.call (target, args.length > 0 ? args[0] : JsValue.undefined (), rest);
                        });
                    }
                    if (name == "bind") {
                        var target = o;
                        return JsValue.native ("bind", (it, self, args) => {
                            var nf = new JsFunction ();
                            var bound_self = args.length > 0 ? args[0] : JsValue.undefined ();
                            nf.native = (it2, s2, a2) => it2.call (target, bound_self, a2);
                            return JsValue.function (nf);
                        });
                    }
                    return JsValue.undefined ();
                default:
                    return Builtins.primitive_member (this, o, name);
            }
        }

        public void set_member (JsValue o, string name, JsValue v) throws ExprError {
            if (o.kind == JsKind.OBJECT) {
                if (o.obj.setter != null && o.obj.setter (name, v)) return;
                o.obj.put (name, v);
                return;
            }
            if (o.kind == JsKind.FUNCTION) {
                o.fn.statics.put (name, v);
                return;
            }
            if (o.kind == JsKind.ARRAY && name == "length") {
                int n = (int) to_number (v);
                while (o.arr.size > n) o.arr.remove_at (o.arr.size - 1);
                while (o.arr.size < n) o.arr.add (JsValue.undefined ());
                return;
            }
            if (o.kind == JsKind.ARRAY) {
                int i = int.parse (name);
                if (i.to_string () == name && i >= 0 && i < 1000000) {
                    while (o.arr.size <= i) o.arr.add (JsValue.undefined ());
                    o.arr[i] = v;
                    return;
                }
            }
            throw new ExprError.RUNTIME ("Cannot set property '%s' on this value", name);
        }

        public double[]? to_doubles (JsValue v) throws ExprError {
            var p = prim (v);
            if (p.kind == JsKind.NUMBER || p.kind == JsKind.BOOL) return { to_number (p) };
            if (p.kind == JsKind.ARRAY) {
                var r = new double[p.arr.size];
                for (int i = 0; i < p.arr.size; i++) {
                    var e = prim (p.arr[i]);
                    if (e.kind == JsKind.ARRAY) throw new ExprError.RUNTIME ("Nested arrays cannot be used as a value");
                    r[i] = to_number (e);
                }
                return r;
            }
            if (p.kind == JsKind.STRING) {
                double d = to_number (p);
                if (!d.is_nan ()) return { d };
            }
            return null;
        }

        public uint next_random () {
            random_state ^= random_state << 13;
            random_state ^= random_state >> 17;
            random_state ^= random_state << 5;
            return random_state;
        }

        public double random01 () {
            return (next_random () & 0xffffff) / 16777216.0;
        }
    }

    namespace Builtins {
        private double arg_num (Interpreter it, JsValue[] args, int i, double fallback = double.NAN) {
            if (i >= args.length || args[i].kind == JsKind.UNDEFINED) return fallback;
            try {
                return it.to_number (it.prim (args[i]));
            } catch (ExprError e) {
                return double.NAN;
            }
        }

        private JsValue fn1 (string name, owned Math1 f) {
            return JsValue.native (name, (it, self, args) => JsValue.number (f (arg_num (it, args, 0))));
        }

        public delegate double Math1 (double x);

        public void install (Interpreter it) {
            var g = it.globals;
            var math = new JsObject ();
            math.class_name = "Math";
            math.put ("PI", JsValue.number (Math.PI));
            math.put ("E", JsValue.number (Math.E));
            math.put ("LN2", JsValue.number (Math.LN2));
            math.put ("LN10", JsValue.number (Math.LN10));
            math.put ("SQRT2", JsValue.number (Math.SQRT2));
            math.put ("SQRT1_2", JsValue.number (Math.sqrt (0.5)));
            math.put ("LOG2E", JsValue.number (1.0 / Math.LN2));
            math.put ("LOG10E", JsValue.number (1.0 / Math.LN10));
            math.put ("abs", fn1 ("abs", (x) => x.abs ()));
            math.put ("sin", fn1 ("sin", (x) => Math.sin (x)));
            math.put ("cos", fn1 ("cos", (x) => Math.cos (x)));
            math.put ("tan", fn1 ("tan", (x) => Math.tan (x)));
            math.put ("asin", fn1 ("asin", (x) => Math.asin (x)));
            math.put ("acos", fn1 ("acos", (x) => Math.acos (x)));
            math.put ("atan", fn1 ("atan", (x) => Math.atan (x)));
            math.put ("sinh", fn1 ("sinh", (x) => Math.sinh (x)));
            math.put ("cosh", fn1 ("cosh", (x) => Math.cosh (x)));
            math.put ("tanh", fn1 ("tanh", (x) => Math.tanh (x)));
            math.put ("sqrt", fn1 ("sqrt", (x) => Math.sqrt (x)));
            math.put ("cbrt", fn1 ("cbrt", (x) => Math.cbrt (x)));
            math.put ("exp", fn1 ("exp", (x) => Math.exp (x)));
            math.put ("log", fn1 ("log", (x) => Math.log (x)));
            math.put ("log2", fn1 ("log2", (x) => Math.log2 (x)));
            math.put ("log10", fn1 ("log10", (x) => Math.log10 (x)));
            math.put ("floor", fn1 ("floor", (x) => Math.floor (x)));
            math.put ("ceil", fn1 ("ceil", (x) => Math.ceil (x)));
            math.put ("round", fn1 ("round", (x) => Math.floor (x + 0.5)));
            math.put ("trunc", fn1 ("trunc", (x) => x < 0 ? Math.ceil (x) : Math.floor (x)));
            math.put ("sign", fn1 ("sign", (x) => x > 0 ? 1 : (x < 0 ? -1 : x)));
            math.put ("atan2", JsValue.native ("atan2", (it2, self, args) => JsValue.number (Math.atan2 (arg_num (it2, args, 0), arg_num (it2, args, 1)))));
            math.put ("pow", JsValue.native ("pow", (it2, self, args) => JsValue.number (Math.pow (arg_num (it2, args, 0), arg_num (it2, args, 1)))));
            math.put ("hypot", JsValue.native ("hypot", (it2, self, args) => {
                double sum = 0;
                for (int i = 0; i < args.length; i++) sum += Math.pow (arg_num (it2, args, i), 2);
                return JsValue.number (Math.sqrt (sum));
            }));
            math.put ("min", JsValue.native ("min", (it2, self, args) => {
                double r = double.INFINITY;
                for (int i = 0; i < args.length; i++) r = double.min (r, arg_num (it2, args, i));
                return JsValue.number (r);
            }));
            math.put ("max", JsValue.native ("max", (it2, self, args) => {
                double r = -double.INFINITY;
                for (int i = 0; i < args.length; i++) r = double.max (r, arg_num (it2, args, i));
                return JsValue.number (r);
            }));
            math.put ("random", JsValue.native ("random", (it2, self, args) => JsValue.number (it2.random01 ())));
            g.define ("Math", JsValue.object (math));
            g.define ("NaN", JsValue.number (double.NAN));
            g.define ("Infinity", JsValue.number (double.INFINITY));
            g.define ("parseFloat", JsValue.native ("parseFloat", (it2, self, args) => {
                var str = args.length > 0 ? it2.to_string (args[0]).strip () : "";
                int end = 0;
                while (end < str.length && (str[end].isdigit () || str[end] == '.' || str[end] == '-' || str[end] == '+' || str[end] == 'e' || str[end] == 'E')) end++;
                double d = double.NAN;
                if (end > 0 && !double.try_parse (str.substring (0, end), out d)) d = double.NAN;
                return JsValue.number (end > 0 ? d : double.NAN);
            }));
            g.define ("parseInt", JsValue.native ("parseInt", (it2, self, args) => {
                var str = args.length > 0 ? it2.to_string (args[0]).strip () : "";
                int radix = (int) arg_num (it2, args, 1, 10);
                if (radix == 0) radix = 10;
                bool neg = false;
                int i = 0;
                if (i < str.length && (str[i] == '-' || str[i] == '+')) {
                    neg = str[i] == '-';
                    i++;
                }
                if (radix == 16 && str.substring (i).down ().has_prefix ("0x")) i += 2;
                double n = 0;
                int digits = 0;
                for (; i < str.length; i++) {
                    int dv = str[i].isdigit () ? str[i] - '0' : (str[i].isalpha () ? str[i].tolower () - 'a' + 10 : 99);
                    if (dv >= radix) break;
                    n = n * radix + dv;
                    digits++;
                }
                return JsValue.number (digits == 0 ? double.NAN : (neg ? -n : n));
            }));
            g.define ("isNaN", JsValue.native ("isNaN", (it2, self, args) => JsValue.boolean (arg_num (it2, args, 0).is_nan ())));
            g.define ("isFinite", JsValue.native ("isFinite", (it2, self, args) => {
                double d = arg_num (it2, args, 0);
                return JsValue.boolean (!d.is_nan () && d.is_infinity () == 0);
            }));
            g.define ("Number", JsValue.native ("Number", (it2, self, args) => JsValue.number (args.length > 0 ? it2.to_number (it2.prim (args[0])) : 0)));
            g.define ("String", JsValue.native ("String", (it2, self, args) => JsValue.string_value (args.length > 0 ? it2.to_string (args[0]) : "")));
            g.define ("Boolean", JsValue.native ("Boolean", (it2, self, args) => JsValue.boolean (args.length > 0 && it2.truthy (args[0]))));
            var array_ctor = JsValue.native ("Array", (it2, self, args) => {
                var l = new Gee.ArrayList<JsValue> ();
                foreach (var a in args) l.add (a);
                return JsValue.array (l);
            });
            array_ctor.fn.statics.put ("isArray", JsValue.native ("isArray", (it2, self, args) => JsValue.boolean (args.length > 0 && args[0].kind == JsKind.ARRAY)));
            array_ctor.fn.statics.put ("from", JsValue.native ("from", (it2, self, args) => {
                var l = new Gee.ArrayList<JsValue> ();
                if (args.length > 0 && args[0].kind == JsKind.ARRAY) l.add_all (args[0].arr);
                else if (args.length > 0 && args[0].kind == JsKind.STRING) {
                    int idx = 0;
                    unichar ch;
                    while (args[0].str.get_next_char (ref idx, out ch)) l.add (JsValue.string_value (ch.to_string ()));
                }
                return JsValue.array (l);
            }));
            g.define ("Array", array_ctor);
            var object_ctor = JsValue.native ("Object", (it2, self, args) => JsValue.object (new JsObject ()));
            object_ctor.fn.statics.put ("keys", JsValue.native ("keys", (it2, self, args) => {
                var l = new Gee.ArrayList<JsValue> ();
                if (args.length > 0 && args[0].kind == JsKind.OBJECT) foreach (var k in args[0].obj.order) l.add (JsValue.string_value (k));
                if (args.length > 0 && args[0].kind == JsKind.ARRAY) for (int i = 0; i < args[0].arr.size; i++) l.add (JsValue.string_value (i.to_string ()));
                return JsValue.array (l);
            }));
            object_ctor.fn.statics.put ("values", JsValue.native ("values", (it2, self, args) => {
                var l = new Gee.ArrayList<JsValue> ();
                if (args.length > 0 && args[0].kind == JsKind.OBJECT) foreach (var k in args[0].obj.order) l.add (args[0].obj.props[k]);
                return JsValue.array (l);
            }));
            object_ctor.fn.statics.put ("assign", JsValue.native ("assign", (it2, self, args) => {
                if (args.length == 0 || args[0].kind != JsKind.OBJECT) return args.length > 0 ? args[0] : JsValue.undefined ();
                for (int i = 1; i < args.length; i++)
                    if (args[i].kind == JsKind.OBJECT) foreach (var k in args[i].obj.order) args[0].obj.put (k, args[i].obj.props[k]);
                return args[0];
            }));
            g.define ("Object", object_ctor);
            var json = new JsObject ();
            json.put ("stringify", JsValue.native ("stringify", (it2, self, args) => JsValue.string_value (args.length > 0 ? stringify (it2, args[0]) : "undefined")));
            g.define ("JSON", JsValue.object (json));
        }

        public string stringify (Interpreter it, JsValue v) throws ExprError {
            var p = it.prim (v);
            switch (p.kind) {
                case JsKind.STRING:
                    return "\"" + p.str.replace ("\\", "\\\\").replace ("\"", "\\\"").replace ("\n", "\\n") + "\"";
                case JsKind.ARRAY:
                    var parts = new string[p.arr.size];
                    for (int i = 0; i < p.arr.size; i++) parts[i] = stringify (it, p.arr[i]);
                    return "[" + string.joinv (",", parts) + "]";
                case JsKind.OBJECT:
                    var sb = new StringBuilder ("{");
                    bool first = true;
                    foreach (var k in p.obj.order) {
                        if (!first) sb.append (",");
                        first = false;
                        sb.append ("\"" + k + "\":" + stringify (it, p.obj.props[k]));
                    }
                    sb.append ("}");
                    return sb.str;
                case JsKind.UNDEFINED:
                case JsKind.FUNCTION:
                    return "null";
                default:
                    return it.to_string (p);
            }
        }

        private int compare_values (Interpreter it, JsValue a, JsValue b, JsValue? cmp) throws ExprError {
            if (cmp != null && cmp.is_callable ()) {
                double r = it.to_number (it.call (cmp, JsValue.undefined (), { a, b }));
                return r < 0 ? -1 : (r > 0 ? 1 : 0);
            }
            return strcmp (it.to_string (a), it.to_string (b));
        }

        private void sort_list (Interpreter it, Gee.ArrayList<JsValue> l, JsValue? cmp) throws ExprError {
            for (int i = 1; i < l.size; i++) {
                var x = l[i];
                int j = i - 1;
                while (j >= 0 && compare_values (it, l[j], x, cmp) > 0) {
                    l[j + 1] = l[j];
                    j--;
                }
                l[j + 1] = x;
            }
        }

        private int norm_index (double d, int len, int fallback) {
            if (d.is_nan ()) return fallback;
            int i = (int) d;
            if (i < 0) i = int.max (0, len + i);
            return int.min (i, len);
        }

        public JsValue primitive_member (Interpreter it, JsValue o, string name) throws ExprError {
            if (o.kind == JsKind.ARRAY) return array_member (it, o, name);
            if (o.kind == JsKind.STRING) return string_member (it, o, name);
            if (o.kind == JsKind.NUMBER) {
                double n = o.num;
                switch (name) {
                    case "toFixed":
                        return JsValue.native ("toFixed", (it2, self, args) => {
                            int digits = (int) arg_num (it2, args, 0, 0);
                            return JsValue.string_value (("%." + digits.clamp (0, 20).to_string () + "f").printf (n));
                        });
                    case "toString":
                        return JsValue.native ("toString", (it2, self, args) => {
                            int radix = (int) arg_num (it2, args, 0, 10);
                            if (radix == 10 || radix < 2 || radix > 36) return JsValue.string_value (Interpreter.number_to_string (n));
                            int64 v = (int64) n;
                            bool neg = v < 0;
                            if (neg) v = -v;
                            var sb = new StringBuilder ();
                            do {
                                int dgt = (int) (v % radix);
                                sb.prepend_c ((char) (dgt < 10 ? '0' + dgt : 'a' + dgt - 10));
                                v /= radix;
                            } while (v > 0);
                            if (neg) sb.prepend_c ('-');
                            return JsValue.string_value (sb.str);
                        });
                    case "toPrecision":
                        return JsValue.native ("toPrecision", (it2, self, args) => JsValue.string_value (("%." + ((int) arg_num (it2, args, 0, 6)).clamp (1, 21).to_string () + "g").printf (n)));
                }
                return JsValue.undefined ();
            }
            if (o.kind == JsKind.BOOL && name == "toString") {
                bool bv = o.b;
                return JsValue.native ("toString", (it2, self, args) => JsValue.string_value (bv ? "true" : "false"));
            }
            return JsValue.undefined ();
        }

        private JsValue string_member (Interpreter it, JsValue o, string name) throws ExprError {
            string s = o.str;
            switch (name) {
                case "length": return JsValue.number (s.char_count ());
                case "toUpperCase": return JsValue.native (name, (it2, self, args) => JsValue.string_value (s.up ()));
                case "toLowerCase": return JsValue.native (name, (it2, self, args) => JsValue.string_value (s.down ()));
                case "trim": return JsValue.native (name, (it2, self, args) => JsValue.string_value (s.strip ()));
                case "charAt":
                    return JsValue.native (name, (it2, self, args) => {
                        int i = (int) arg_num (it2, args, 0, 0);
                        if (i < 0 || i >= s.char_count ()) return JsValue.string_value ("");
                        return JsValue.string_value (s.get_char (s.index_of_nth_char (i)).to_string ());
                    });
                case "charCodeAt":
                    return JsValue.native (name, (it2, self, args) => {
                        int i = (int) arg_num (it2, args, 0, 0);
                        if (i < 0 || i >= s.char_count ()) return JsValue.number (double.NAN);
                        return JsValue.number ((double) s.get_char (s.index_of_nth_char (i)));
                    });
                case "indexOf":
                    return JsValue.native (name, (it2, self, args) => {
                        var needle = args.length > 0 ? it2.to_string (args[0]) : "undefined";
                        int b = s.index_of (needle);
                        return JsValue.number (b < 0 ? -1 : s.substring (0, b).char_count ());
                    });
                case "lastIndexOf":
                    return JsValue.native (name, (it2, self, args) => {
                        var needle = args.length > 0 ? it2.to_string (args[0]) : "undefined";
                        int b = s.last_index_of (needle);
                        return JsValue.number (b < 0 ? -1 : s.substring (0, b).char_count ());
                    });
                case "includes": return JsValue.native (name, (it2, self, args) => JsValue.boolean (args.length > 0 && s.contains (it2.to_string (args[0]))));
                case "startsWith": return JsValue.native (name, (it2, self, args) => JsValue.boolean (args.length > 0 && s.has_prefix (it2.to_string (args[0]))));
                case "endsWith": return JsValue.native (name, (it2, self, args) => JsValue.boolean (args.length > 0 && s.has_suffix (it2.to_string (args[0]))));
                case "slice":
                case "substring":
                case "substr":
                    string which = name;
                    return JsValue.native (name, (it2, self, args) => {
                        int len = s.char_count ();
                        int a, b;
                        if (which == "substr") {
                            a = norm_index (arg_num (it2, args, 0, 0), len, 0);
                            b = int.min (len, a + (int) arg_num (it2, args, 1, len));
                        } else if (which == "slice") {
                            a = norm_index (arg_num (it2, args, 0, 0), len, 0);
                            b = norm_index (arg_num (it2, args, 1, len), len, len);
                        } else {
                            a = ((int) arg_num (it2, args, 0, 0)).clamp (0, len);
                            b = ((int) arg_num (it2, args, 1, len)).clamp (0, len);
                            if (a > b) {
                                int t = a;
                                a = b;
                                b = t;
                            }
                        }
                        if (b <= a) return JsValue.string_value ("");
                        int ba = s.index_of_nth_char (a), bb = s.index_of_nth_char (b);
                        return JsValue.string_value (s.substring (ba, bb - ba));
                    });
                case "split":
                    return JsValue.native (name, (it2, self, args) => {
                        var l = new Gee.ArrayList<JsValue> ();
                        if (args.length == 0 || args[0].kind == JsKind.UNDEFINED) {
                            l.add (JsValue.string_value (s));
                        } else {
                            var sep = it2.to_string (args[0]);
                            if (sep == "") {
                                int idx = 0;
                                unichar ch;
                                while (s.get_next_char (ref idx, out ch)) l.add (JsValue.string_value (ch.to_string ()));
                            } else {
                                foreach (var part in s.split (sep)) l.add (JsValue.string_value (part));
                            }
                        }
                        return JsValue.array (l);
                    });
                case "replace":
                case "replaceAll":
                    bool all = name == "replaceAll";
                    return JsValue.native (name, (it2, self, args) => {
                        if (args.length < 2) return JsValue.string_value (s);
                        var from = it2.to_string (args[0]);
                        var to = it2.to_string (args[1]);
                        if (all) return JsValue.string_value (s.replace (from, to));
                        int i = s.index_of (from);
                        if (i < 0) return JsValue.string_value (s);
                        return JsValue.string_value (s.substring (0, i) + to + s.substring (i + from.length));
                    });
                case "repeat":
                    return JsValue.native (name, (it2, self, args) => {
                        int n = ((int) arg_num (it2, args, 0, 0)).clamp (0, 10000);
                        var sb = new StringBuilder ();
                        for (int i = 0; i < n; i++) sb.append (s);
                        return JsValue.string_value (sb.str);
                    });
                case "padStart":
                case "padEnd":
                    bool start = name == "padStart";
                    return JsValue.native (name, (it2, self, args) => {
                        int target = (int) arg_num (it2, args, 0, 0);
                        var pad = args.length > 1 ? it2.to_string (args[1]) : " ";
                        if (pad == "") pad = " ";
                        var sb = new StringBuilder ();
                        while (sb.str.char_count () + s.char_count () < target) sb.append (pad);
                        var fill = sb.str;
                        int need = target - s.char_count ();
                        if (need <= 0) return JsValue.string_value (s);
                        fill = fill.substring (0, fill.index_of_nth_char (need));
                        return JsValue.string_value (start ? fill + s : s + fill);
                    });
                case "concat":
                    return JsValue.native (name, (it2, self, args) => {
                        var sb = new StringBuilder (s);
                        foreach (var a in args) sb.append (it2.to_string (a));
                        return JsValue.string_value (sb.str);
                    });
                case "toString":
                case "valueOf":
                    return JsValue.native (name, (it2, self, args) => JsValue.string_value (s));
            }
            return JsValue.undefined ();
        }

        private JsValue array_member (Interpreter it, JsValue o, string name) throws ExprError {
            var a = o.arr;
            switch (name) {
                case "length": return JsValue.number (a.size);
                case "push":
                    return JsValue.native (name, (it2, self, args) => {
                        foreach (var x in args) a.add (x);
                        return JsValue.number (a.size);
                    });
                case "pop": return JsValue.native (name, (it2, self, args) => a.size > 0 ? a.remove_at (a.size - 1) : JsValue.undefined ());
                case "shift": return JsValue.native (name, (it2, self, args) => a.size > 0 ? a.remove_at (0) : JsValue.undefined ());
                case "unshift":
                    return JsValue.native (name, (it2, self, args) => {
                        for (int i = args.length - 1; i >= 0; i--) a.insert (0, args[i]);
                        return JsValue.number (a.size);
                    });
                case "slice":
                    return JsValue.native (name, (it2, self, args) => {
                        int s0 = norm_index (arg_num (it2, args, 0, 0), a.size, 0);
                        int s1 = norm_index (arg_num (it2, args, 1, a.size), a.size, a.size);
                        var l = new Gee.ArrayList<JsValue> ();
                        for (int i = s0; i < s1; i++) l.add (a[i]);
                        return JsValue.array (l);
                    });
                case "splice":
                    return JsValue.native (name, (it2, self, args) => {
                        int s0 = norm_index (arg_num (it2, args, 0, 0), a.size, 0);
                        int count = args.length > 1 ? ((int) arg_num (it2, args, 1, 0)).clamp (0, a.size - s0) : a.size - s0;
                        var removed = new Gee.ArrayList<JsValue> ();
                        for (int i = 0; i < count; i++) removed.add (a.remove_at (s0));
                        for (int i = args.length - 1; i >= 2; i--) a.insert (s0, args[i]);
                        return JsValue.array (removed);
                    });
                case "concat":
                    return JsValue.native (name, (it2, self, args) => {
                        var l = new Gee.ArrayList<JsValue> ();
                        l.add_all (a);
                        foreach (var x in args) {
                            if (x.kind == JsKind.ARRAY) l.add_all (x.arr);
                            else l.add (x);
                        }
                        return JsValue.array (l);
                    });
                case "join":
                    return JsValue.native (name, (it2, self, args) => {
                        var sep = args.length > 0 && args[0].kind != JsKind.UNDEFINED ? it2.to_string (args[0]) : ",";
                        var parts = new string[a.size];
                        for (int i = 0; i < a.size; i++) parts[i] = a[i].is_nullish () ? "" : it2.to_string (a[i]);
                        return JsValue.string_value (string.joinv (sep, parts));
                    });
                case "indexOf":
                case "includes":
                    bool inc = name == "includes";
                    return JsValue.native (name, (it2, self, args) => {
                        var needle = args.length > 0 ? args[0] : JsValue.undefined ();
                        for (int i = 0; i < a.size; i++) if (it2.strict_equals (a[i], needle)) return inc ? JsValue.boolean (true) : JsValue.number (i);
                        return inc ? JsValue.boolean (false) : JsValue.number (-1);
                    });
                case "reverse":
                    return JsValue.native (name, (it2, self, args) => {
                        for (int i = 0, j = a.size - 1; i < j; i++, j--) {
                            var t = a[i];
                            a[i] = a[j];
                            a[j] = t;
                        }
                        return o;
                    });
                case "sort":
                    return JsValue.native (name, (it2, self, args) => {
                        sort_list (it2, a, args.length > 0 ? args[0] : null);
                        return o;
                    });
                case "map":
                case "filter":
                case "forEach":
                case "some":
                case "every":
                case "find":
                case "findIndex":
                    string which = name;
                    return JsValue.native (name, (it2, self, args) => {
                        if (args.length == 0 || !args[0].is_callable ()) throw new ExprError.RUNTIME ("%s needs a function", which);
                        var f = args[0];
                        var l = new Gee.ArrayList<JsValue> ();
                        var snapshot = new Gee.ArrayList<JsValue> ();
                        snapshot.add_all (a);
                        for (int i = 0; i < snapshot.size; i++) {
                            var r = it2.call (f, JsValue.undefined (), { snapshot[i], JsValue.number (i), o });
                            switch (which) {
                                case "map": l.add (r); break;
                                case "filter": if (it2.truthy (r)) l.add (snapshot[i]); break;
                                case "some": if (it2.truthy (r)) return JsValue.boolean (true); break;
                                case "every": if (!it2.truthy (r)) return JsValue.boolean (false); break;
                                case "find": if (it2.truthy (r)) return snapshot[i]; break;
                                case "findIndex": if (it2.truthy (r)) return JsValue.number (i); break;
                            }
                        }
                        switch (which) {
                            case "map":
                            case "filter": return JsValue.array (l);
                            case "some": return JsValue.boolean (false);
                            case "every": return JsValue.boolean (true);
                            case "findIndex": return JsValue.number (-1);
                            default: return JsValue.undefined ();
                        }
                    });
                case "reduce":
                    return JsValue.native (name, (it2, self, args) => {
                        if (args.length == 0 || !args[0].is_callable ()) throw new ExprError.RUNTIME ("reduce needs a function");
                        int start = 0;
                        JsValue acc;
                        if (args.length > 1) acc = args[1];
                        else {
                            if (a.size == 0) throw new ExprError.RUNTIME ("reduce of an empty array");
                            acc = a[0];
                            start = 1;
                        }
                        for (int i = start; i < a.size; i++) acc = it2.call (args[0], JsValue.undefined (), { acc, a[i], JsValue.number (i), o });
                        return acc;
                    });
                case "toString":
                    return JsValue.native (name, (it2, self, args) => JsValue.string_value (it2.to_string (o)));
            }
            return JsValue.undefined ();
        }
    }
}
