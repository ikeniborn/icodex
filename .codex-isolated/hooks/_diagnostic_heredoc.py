"""Static effect checks for the documented diagnostic interpreter subset."""
import ast
import posixpath


DATA = ('data', None)
UNKNOWN = ('unknown', None)
BUILTINS = set('print len str int float bool list tuple dict set sorted enumerate range zip sum min max any all'.split())
METHODS = set('split splitlines strip lstrip rstrip startswith endswith lower upper replace items keys values get append add setdefault'.split())
FILESYSTEM = {'read_text', 'read_bytes', 'exists', 'is_file', 'is_dir'}


class AccessRefusal(Exception):
    def __init__(self, category='indeterminate_access', rule=None, line=1):
        self.category, self.rule, self.line = category, rule, line


class PythonAnalysis:
    def __init__(self, sensitive):
        self.sensitive = sensitive
        self.env = {name: ('call', name) for name in BUILTINS}
        self.reserved = set(BUILTINS)

    def refuse(self, node):
        raise AccessRefusal(line=getattr(node, 'lineno', 1))

    def ordinary(self, value, node):
        if value[0] in {'call', 'module'}:
            self.refuse(node)
        return value

    def bind(self, target, value):
        self.ordinary(value, target)
        if isinstance(target, ast.Name):
            if target.id in self.reserved:
                self.refuse(target)
            self.env[target.id] = value
        elif isinstance(target, (ast.Tuple, ast.List)):
            for item in target.elts:
                self.bind(item, DATA)
        elif isinstance(target, ast.Subscript):
            if self.expr(target.value)[0] != 'data':
                self.refuse(target)
            self.expr(target.slice)
        else:
            self.refuse(target)

    def block(self, nodes):
        for node in nodes:
            self.statement(node)

    def statement(self, node):
        if isinstance(node, ast.Import):
            for item in node.names:
                if item.name not in {'pathlib', 'json'} or item.asname or item.name in self.env:
                    self.refuse(node)
                self.env[item.name] = ('module', item.name)
                self.reserved.add(item.name)
        elif isinstance(node, ast.ImportFrom):
            expected = {'pathlib': 'Path', 'collections': 'Counter'}
            if node.level or len(node.names) != 1 or expected.get(node.module) != node.names[0].name:
                self.refuse(node)
            item = node.names[0]
            if item.asname or item.name in self.env:
                self.refuse(node)
            self.env[item.name] = ('call', item.name)
            self.reserved.add(item.name)
        elif isinstance(node, ast.Expr):
            self.expr(node.value)
        elif isinstance(node, (ast.Assign, ast.AnnAssign)):
            if isinstance(node, ast.AnnAssign):
                if not (isinstance(node.annotation, ast.Name) and node.annotation.id in
                        {'str', 'int', 'float', 'bool', 'list', 'tuple', 'dict', 'set', 'Path'} and
                        node.annotation.id in self.reserved):
                    self.expr(node.annotation)
            value = self.expr(node.value) if node.value else DATA
            for target in node.targets if isinstance(node, ast.Assign) else [node.target]:
                self.bind(target, value)
        elif isinstance(node, ast.If):
            self.expr(node.test)
            initial = self.env.copy()
            self.block(node.body)
            left = self.env.copy()
            self.env = initial.copy()
            self.block(node.orelse)
            right = self.env
            self.env = {key: left.get(key, UNKNOWN) if left.get(key, UNKNOWN) == right.get(key, UNKNOWN) else UNKNOWN
                        for key in left.keys() | right.keys()}
        elif isinstance(node, ast.For):
            self.expr(node.iter)
            initial = self.env.copy()
            for item in ast.walk(node):
                if isinstance(item, ast.Name) and isinstance(item.ctx, ast.Store):
                    if item.id in self.reserved:
                        self.refuse(item)
                    self.env[item.id] = UNKNOWN
            self.bind(node.target, DATA)
            self.block(node.body)
            final = self.env.copy()
            self.env = {key: initial.get(key, UNKNOWN) if initial.get(key, UNKNOWN) == final.get(key, UNKNOWN) else UNKNOWN
                        for key in initial.keys() | final.keys()}
            self.block(node.orelse)
        else:
            self.refuse(node)

    def expr(self, node, callable_position=False):
        if isinstance(node, ast.Constant):
            result = ('string', node.value) if isinstance(node.value, str) else DATA
        elif isinstance(node, ast.Name):
            result = self.env.get(node.id, UNKNOWN)
        elif isinstance(node, ast.Attribute):
            receiver = self.expr(node.value, callable_position=True)
            if receiver == ('module', 'pathlib') and node.attr == 'Path':
                result = ('call', 'Path')
            elif receiver == ('module', 'json') and node.attr in {'loads', 'dumps'}:
                result = ('call', 'json.' + node.attr)
            else:
                self.refuse(node)
        elif isinstance(node, ast.Call):
            result = self.call(node)
        elif isinstance(node, ast.BinOp):
            left, right = self.expr(node.left), self.expr(node.right)
            if isinstance(node.op, ast.Add) and left[0] == right[0] == 'string':
                result = ('string', left[1] + right[1])
            elif isinstance(node.op, ast.Div) and left[0] == 'path' and right[0] == 'string':
                result = ('path', posixpath.join(left[1], right[1]))
            else:
                result = DATA
        elif isinstance(node, (ast.List, ast.Tuple, ast.Set)):
            for item in node.elts:
                self.expr(item)
            result = DATA
        elif isinstance(node, ast.Dict):
            for key, value in zip(node.keys, node.values):
                if key:
                    self.expr(key)
                self.expr(value)
            result = DATA
        elif isinstance(node, ast.Subscript):
            value = self.expr(node.value)
            self.expr(node.slice)
            result = DATA if value[0] in {'data', 'string'} else UNKNOWN
        elif isinstance(node, ast.Slice):
            for part in (node.lower, node.upper, node.step):
                if part:
                    self.expr(part)
            result = DATA
        elif isinstance(node, (ast.ListComp, ast.SetComp, ast.DictComp, ast.GeneratorExp)):
            initial = self.env.copy()
            if isinstance(node, ast.GeneratorExp):
                # Deferred bodies cannot retain an optimistic current path binding.
                self.env = {key: value if key in self.reserved else UNKNOWN
                            for key, value in self.env.items()}
            for generator in node.generators:
                if generator.is_async:
                    self.refuse(node)
                self.expr(generator.iter)
                self.bind(generator.target, DATA)
                for condition in generator.ifs:
                    self.expr(condition)
            if isinstance(node, ast.DictComp):
                self.expr(node.key)
                self.expr(node.value)
            else:
                self.expr(node.elt)
            self.env = initial
            result = DATA
        elif isinstance(node, (ast.Compare, ast.BoolOp, ast.UnaryOp, ast.IfExp, ast.JoinedStr, ast.FormattedValue)):
            for child in ast.iter_child_nodes(node):
                if isinstance(child, ast.expr):
                    self.expr(child)
            result = DATA
        else:
            self.refuse(node)
        return result if callable_position else self.ordinary(result, node)

    def call(self, node):
        args = [self.expr(arg) for arg in node.args]
        for keyword in node.keywords:
            if keyword.arg is None:
                self.refuse(node)
            self.expr(keyword.value)
        if isinstance(node.func, ast.Attribute):
            receiver = self.expr(node.func.value, callable_position=True)
            if receiver[0] == 'path' and node.func.attr in FILESYSTEM:
                blocked, rule = self.sensitive(receiver[1])
                if blocked:
                    raise AccessRefusal('protected_path', rule, node.lineno)
                return DATA
            if receiver[0] in {'data', 'string'} and node.func.attr in METHODS:
                return DATA
        function = self.expr(node.func, callable_position=True)
        if function[0] != 'call':
            self.refuse(node)
        if function[1] == 'Path':
            if node.keywords or not args or any(arg[0] not in {'string', 'path'} for arg in args):
                self.refuse(node)
            return ('path', posixpath.join(*(arg[1] for arg in args)))
        if function[1] == 'str' and len(args) == 1 and args[0][0] in {'string', 'path'}:
            return ('string', args[0][1])
        return DATA


def analyze_python(body, sensitive_path):
    try:
        PythonAnalysis(sensitive_path).block(ast.parse(body).body)
        return None, None, 1
    except AccessRefusal as error:
        return error.category, error.rule, error.line
    except (SyntaxError, ValueError, RecursionError):
        return 'indeterminate_access', None, 1


def shell_commands(body):
    """Tokenize the restricted grammar while preserving quote effects."""
    commands, words, word = [], [], []
    quote, started, line, origin, i = None, False, 1, 1, 0
    def end_word():
        nonlocal started, word
        if started:
            words.append(''.join(word))
        started, word = False, []
    while i < len(body):
        char = body[i]
        if quote == "'":
            if char == "'":
                quote = None
            else:
                word.append(char)
        elif char == '\\' and (quote is None or i + 1 < len(body) and body[i + 1] in '$`"\\\n'):
            i += 1
            if i >= len(body):
                raise AccessRefusal(line=line)
            if body[i] == '\n':
                line += 1
            else:
                word.append(body[i])
                started = True
        elif char in '$`' or quote is None and char in '*?[]{}~|&<>()':
            raise AccessRefusal(line=line)
        elif quote == '"':
            if char == '"':
                quote = None
            else:
                word.append(char)
        elif char in "'\"":
            quote, started = char, True
        elif char == '#' and not started:
            end = body.find('\n', i)
            i = len(body) if end < 0 else end
            continue
        elif char in ';\n':
            end_word()
            if words:
                commands.append((origin, words))
            words = []
            origin = line + (char == '\n')
        elif char.isspace():
            end_word()
        else:
            word.append(char)
            started = True
        if char == '\n':
            line += 1
        i += 1
    if quote:
        raise AccessRefusal(line=line)
    end_word()
    if words:
        commands.append((origin, words))
    return commands


def analyze_bash(body, sensitive_path):
    try:
        allowed = {'echo', 'printf', 'pwd', 'cat', 'head', 'tail', 'wc', 'ls'}
        flags = {'cat': set('nbsETvA'), 'wc': set('lwcmL'), 'ls': set('laAhdnistr1')}
        for line, words in shell_commands(body):
            name = words[0]
            if name.startswith(('/bin/', '/usr/bin/')):
                name = name.rsplit('/', 1)[1]
                if words[0] not in {'/bin/' + name, '/usr/bin/' + name}:
                    raise AccessRefusal(line=line)
            if name not in allowed:
                raise AccessRefusal(line=line)
            args = words[1:]
            if name in {'echo', 'printf'}:
                if name == 'printf' and args:
                    if args[0].startswith('-v'):
                        raise AccessRefusal(line=line)
                    format_text = args[1] if args[0] == '--' and len(args) > 1 else args[0]
                    offset = 0
                    while offset < len(format_text):
                        if format_text[offset] != '%':
                            offset += 1
                            continue
                        offset += 1
                        if offset < len(format_text) and format_text[offset] == '%':
                            offset += 1
                            continue
                        while offset < len(format_text) and format_text[offset] in '-+ #0123456789.*':
                            offset += 1
                        if offset < len(format_text) and format_text[offset] == 'n':
                            raise AccessRefusal(line=line)
                        offset += 1
                continue
            if name == 'pwd':
                if args:
                    raise AccessRefusal(line=line)
                continue
            options, index = True, 0
            while index < len(args):
                item = args[index]
                if options and item == '--':
                    options = False
                elif options and item.startswith('-') and item != '-':
                    if name in {'head', 'tail'} and item in {'-n', '-c'}:
                        index += 1
                        if index >= len(args) or not args[index].lstrip('+-').isdigit():
                            raise AccessRefusal(line=line)
                    elif name not in flags or len(item) < 2 or any(c not in flags[name] for c in item[1:]):
                        raise AccessRefusal(line=line)
                else:
                    blocked, rule = sensitive_path(item)
                    if blocked:
                        raise AccessRefusal('protected_path', rule, line)
                index += 1
        return None, None, 1
    except AccessRefusal as error:
        return error.category, error.rule, error.line
