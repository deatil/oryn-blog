package jinja

import "core:testing"

@(test)
literals_render_like_python :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    check(t, "{{ 42 }}|{{ -7 }}|{{ 1_000 }}|{{ 0x1F }}|{{ 0o17 }}|{{ 0b101 }}",
        "42|-7|1000|31|15|5")
    check(t, "{{ 1.5 }}|{{ 2.0 }}|{{ 0.1 }}|{{ 1e3 }}|{{ 1.5e-5 }}|{{ 1e16 }}",
        "1.5|2.0|0.1|1000.0|1.5e-05|1e+16")
    check(t, "{{ 'a' }}{{ \"b\" }}{{ 'c' 'd' }}", "abcd")
    check(t, `{{ 'tab\there' }}|{{ "q\"q" }}|{{ 'back\\slash' }}|{{ 'é' }}`,
        "tab\there|q\"q|back\\slash|é")
    check(t, "{{ true }} {{ false }} {{ True }} {{ none }} {{ None }}",
        "True False True None None")
    check(t, "{{ [1, 'a', none] }}|{{ (1,) }}|{{ () }}|{{ (1, 2) }}",
        "[1, 'a', None]|(1,)|()|(1, 2)")
    check(t, "{{ {'a': 1, 'b': [2]} }}|{{ {} }}", "{'a': 1, 'b': [2]}|{}")
    check(t, `{{ ["it's"] }}|{{ ['say "hi"'] }}|{{ ['a\nb'] }}`,
        `["it's"]|['say "hi"']|['a\nb']`)
    check(t, "{{ 1, 2 }}", "(1, 2)")
    check(t, "{{ [1, 2,] }}{{ {'a': 1,} }}", "[1, 2]{'a': 1}")
}

@(test)
arithmetic_follows_python :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    check(t, "{{ 1 + 2 }} {{ 5 - 7 }} {{ 3 * 4 }} {{ 7 / 2 }} {{ 7 // 2 }} {{ 7 % 3 }}",
        "3 -2 12 3.5 3 1")
    check(t, "{{ -7 // 2 }} {{ -7 % 3 }} {{ 7 % -3 }} {{ 2 ** 10 }} {{ 2 ** -1 }}",
        "-4 2 -2 1024 0.5")
    check(t, "{{ 4 / 2 }} {{ 1 + 1.5 }} {{ 7.5 // 2 }} {{ -7.5 % 2 }}", "2.0 2.5 3.0 0.5")
    check(t, "{{ 2 ** 3 ** 2 }} {{ -2 ** 2 }} {{ 2 * 3 + 4 }} {{ 2 * (3 + 4) }}",
        "64 4 10 14")
    check(t, "{{ 'ab' + 'cd' }} {{ 'ab' * 3 }} {{ [1] + [2] }} {{ [0] * 3 }}",
        "abcd ababab [1, 2] [0, 0, 0]")
    check(t, "{{ 1 ~ 2 ~ 'x' }} {{ none ~ true }} {{ missing ~ 'a' }}", "12x NoneTrue a")
    check(t, "{{ true + 1 }} {{ 0.1 + 0.2 }} {{ 10 / 4 * 2 }}", "2 0.30000000000000004 5.0")
    check(t, "{{ -(3) }} {{ +3 }} {{ - 1.5 }}", "-3 3 -1.5")
    check_error(t, "{{ 1 / 0 }}", "division by zero")
    check_error(t, "{{ 1 // 0 }}", "integer division or modulo by zero")
    check_error(t, "{{ 'a' + 1 }}", "can only concatenate str (not \"int\") to str")
    check_error(t, "{{ 'a' - 1 }}", "unsupported operand type(s) for -: 'str' and 'int'")
    check_error(t, "{{ [1] + (1,) }}", "can only concatenate list (not \"tuple\") to list")
}

@(test)
comparisons_and_logic :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    check(t, "{{ 1 < 2 }} {{ 2 <= 1 }} {{ 1 == 1.0 }} {{ 'a' != 'b' }} {{ 3 > 2 > 1 }}",
        "True False True True True")
    check(t, "{{ 1 < 2 < 2 }} {{ [1, 2] < [1, 3] }} {{ 'abc' < 'abd' }} {{ true == 1 }}",
        "False True True True")
    check(t, "{{ 2 in [1, 2] }} {{ 'b' in 'abc' }} {{ 'k' in {'k': 1} }} {{ 3 not in [3] }}",
        "True True True False")
    check(t, "{{ 1 and 2 }} {{ 0 and 2 }} {{ 0 or 'x' }} {{ '' or [] }} {{ not 0 }}",
        "2 0 x [] True")
    check(t, "{{ none or 'd' }} {{ not none and 1 }} {{ not 1 == 2 }}", "d 1 True")
    check(t, "{{ 'y' if true else 'n' }} {{ 'y' if 0 else 'n' }} [{{ 'y' if false }}]",
        "y n []")
    check(t, "{{ 1 if 0 else 2 if 0 else 3 }}", "3")
    check(t, "{{ (1, 2) == (1, 2) }} {{ (1, 2) == [1, 2] }} {{ {'a': 1} == {'a': 1} }}",
        "True False True")
    check(t, "{{ missing == missing }} {{ missing is undefined }}", "True True")
    check_error(t, "{{ 1 < 'a' }}", "'<' not supported between instances of 'int' and 'str'")
    check_error(t, "{{ 1 in 'abc' }}", "'in <string>' requires string as left operand")
    check_error(t, "{{ 1 in 3 }}", "argument of type 'int' is not iterable")
}

@(test)
attribute_and_item_access :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    ctx := "{'d': {'a': 1, 'items': 'x', 'n': {'m': 2}}, 'l': [10, 20, 30], 's': 'hello'}"
    check(t, "{{ d.a }} {{ d['a'] }} {{ d.n.m }} {{ d['n']['m'] }} {{ l[0] }} {{ l.1 }}",
        "1 1 2 2 10 20", ctx)
    check(t, "{{ l[-1] }} {{ s[1] }} {{ s[-1] }} {{ l[1:] }} {{ l[:-1] }} {{ l[::-1] }}",
        "30 e o [20, 30] [10, 20] [30, 20, 10]", ctx)
    check(t, "{{ s[1:3] }} {{ s[::2] }} {{ s[10:] }} {{ l[5:9] }}", "el hlo  []", ctx)
    check(t, "{{ d['items'] }} {{ d.items() | list }}",
        "x [('a', 1), ('items', 'x'), ('n', {'m': 2})]", ctx)
    check(t, "[{{ d.missing }}] [{{ l[7] }}] [{{ d['x'] }}]", "[] [] []", ctx)
    check_error(t, "{{ d.missing.deeper }}", "'dict object' has no attribute 'missing'", ctx)
    check_error(t, "{{ nothing.attr }}", "'nothing' is undefined")
    check_error(t, "{{ nothing['k'] }}", "'nothing' is undefined")
    check_error(t, "{{ none.attr.x }}", "'None' has no attribute 'attr'")
}

@(test)
method_calls_on_builtins :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    check(t, "{{ 'Hello'.upper() }} {{ 'Hello'.lower() }} {{ 'hello world'.title() }}",
        "HELLO hello Hello World")
    check(t, "{{ \"they're\".title() }} {{ 'aBC'.capitalize() }} {{ 'aB'.swapcase() }}",
        "They'Re Abc Ab")
    check(t, "[{{ '  x  '.strip() }}] [{{ 'xxaxx'.strip('x') }}] [{{ '  x'.lstrip() }}]",
        "[x] [a] [x]")
    check(t, "{{ 'a,b,,c'.split(',') }} {{ ' a  b '.split() }} {{ 'a b c'.split(' ', 1) }}",
        "['a', 'b', '', 'c'] ['a', 'b'] ['a', 'b c']")
    check(t, "{{ 'a b c'.rsplit(' ', 1) }} {{ 'a b  c'.rsplit(None, 1) }}",
        "['a b', 'c'] ['a b', 'c']")
    check(t, "{{ '-'.join(['a', 'b']) }} {{ 'aaa'.replace('a', 'b', 2) }}", "a-b bba")
    check(t, "{{ 'abc'.startswith('ab') }} {{ 'abc'.endswith(('x', 'c')) }}", "True True")
    check(t, "{{ 'abcabc'.find('c') }} {{ 'abc'.find('z') }} {{ 'abcabc'.rfind('b') }}",
        "2 -1 4")
    check(t, "{{ 'banana'.count('a') }} {{ 'a\\nb\\r\\nc'.splitlines() }}",
        "3 ['a', 'b', 'c']")
    check(t, "{{ '{} and {}'.format(1, 'x') }} {{ '{0}{0}'.format('ab') }}", "1 and x abab")
    check(t, "{{ '{name}!'.format(name='Ann') }} {{ '{:>5}|{:<4}|{:^5}'.format('a', 'b', 'c') }}",
        "Ann!     a|b   |  c  ")
    check(t, "{{ '{:.2f} {:5d} {:05.1f} {:,}'.format(3.14159, 42, 2.5, 1234567) }}",
        "3.14    42 002.5 1,234,567")
    check(t, "{{ '{:x} {:#b} {:e} {:%}'.format(255, 5, 12345.678, 0.25) }}",
        "ff 0b101 1.234568e+04 25.000000%")
    check(t, "{{ '12'.isdigit() }} {{ 'ab'.isalpha() }} {{ 'Ab'.islower() }} {{ ''.isdigit() }}",
        "True True False False")
    check(t, "{{ 'ab'.center(6, '*') }} {{ '7'.zfill(3) }} {{ 'a'.ljust(3) }}|", "**ab** 007 a  |")
    check(t, "{{ 'a=b'.partition('=') }} {{ 'x.txt'.removesuffix('.txt') }}",
        "('a', '=', 'b') x")
    check(t, "{{ [1, 2, 1].count(1) }} {{ ['a', 'b'].index('b') }}", "2 1")
    check(t, "{{ {'a': 1}.get('a') }} {{ {'a': 1}.get('b', 'z') }} {{ {'a': 1}.get('b') }}",
        "1 z None")
    check(t, "{{ {'a': 1, 'b': 2}.keys() | list }} {{ {'a': 1}.values() | list }}",
        "['a', 'b'] [1]")
    check(t, "{% set l = [3] %}{% do l.append(4) %}{% do l.extend([5]) %}{{ l }}",
        "[3, 4, 5]")
    check(t, "{% set d = {} %}{% do d.update({'a': 1}) %}{% do d.setdefault('b', 2) %}{{ d }}",
        "{'a': 1, 'b': 2}")
    check(t, "{% set l = [1, 2, 3] %}{{ l.pop() }}{{ l }}", "3[1, 2]")
    check(t, "{{ 5.0.is_integer() }}", "True")
}

@(test)
calls_with_all_argument_kinds :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    check(t, "{% macro f(a, b=2) %}{{ a }}-{{ b }}{% endmacro %}" +
        "{{ f(1) }} {{ f(1, 3) }} {{ f(b=5, a=4) }} {{ f(*[7, 8]) }} {{ f(**{'a': 9}) }}",
        "1-2 1-3 4-5 7-8 9-2")
    check(t, "{{ dict(a=1, **{'b': 2}) }}", "{'a': 1, 'b': 2}")
    check(t, "{{ range(*[1, 4]) | list }}", "[1, 2, 3]")
    check_error(t, "{{ 42() }}", "'int' object is not callable")
    check_error(t, "{{ nope() }}", "'nope' is undefined")
}

@(test)
integers_are_64_bit_and_overflow_is_an_error :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    check(t, "{{ 2 ** 62 }} {{ (-1) ** 1000000000001 }} {{ 1 ** 999999999999 }}",
        "4611686018427387904 -1 1")
    check(t, "{{ 2.0 ** 100 }}", "1.2676506002282294e+30")
    check_error(t, "{{ 2 ** 64 }}", "integer overflow")
    check_error(t, "{{ 9223372036854775807 + 1 }}", "integer overflow")
    check_error(t, "{{ 99999999999999999999 }}", "integer literal out of range")
}

@(test)
string_escapes_decode :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    check(t, "{{ '\\u00e9\\x41\\U0001F600' }}|{{ '\\q' }}", "éA😀|\\q")
}
