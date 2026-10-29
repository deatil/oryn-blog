package jinja

import "core:testing"

@(test)
if_elif_else :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    src := "{% if n > 2 %}big{% elif n == 2 %}two{% elif n %}small{% else %}zero{% endif %}"
    check(t, src, "big", "{'n': 5}")
    check(t, src, "two", "{'n': 2}")
    check(t, src, "small", "{'n': 1}")
    check(t, src, "zero", "{'n': 0}")
    check(t, "{% if missing %}a{% else %}b{% endif %}", "b")
    check(t, "{% if [] %}a{% endif %}{% if {} %}b{% endif %}{% if 'x' %}c{% endif %}", "c")
}

@(test)
for_loops_and_loop_object :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    check(t, "{% for x in 'abc' %}{{ loop.index }}{{ loop.index0 }}{{ loop.revindex }}" +
        "{{ loop.revindex0 }}{{ loop.first }}{{ loop.last }}{{ loop.length }};{% endfor %}",
        "1032TrueFalse3;2121FalseFalse3;3210FalseTrue3;")
    check(t, "{% for x in [1, 2, 3] %}{{ loop.cycle('odd', 'even') }} {% endfor %}",
        "odd even odd ")
    check(t, "{% for x in [1, 2, 3] %}{{ loop.previtem }}-{{ loop.nextitem }} {% endfor %}",
        "-2 1-3 2- ")
    check(t, "{% for x in [1, 1, 2, 3, 3] %}{% if loop.changed(x) %}{{ x }}{% endif %}" +
        "{% endfor %}", "123")
    check(t, "{% for k, v in {'a': 1, 'b': 2}.items() %}{{ k }}={{ v }};{% endfor %}",
        "a=1;b=2;")
    check(t, "{% for k in {'a': 1, 'b': 2} %}{{ k }}{% endfor %}", "ab")
    check(t, "{% for a, b in [(1, 2), (3, 4)] %}{{ a + b }},{% endfor %}", "3,7,")
    check(t, "{% for x in [] %}x{% else %}empty{% endfor %}", "empty")
    check(t, "{% for x in missing %}x{% else %}none{% endfor %}", "none")
    check(t, "{% for x in range(10) if x is odd %}{{ x }}{{ loop.index }}{{ loop.length }}," +
        "{% endfor %}", "115,325,535,745,955,")
    check(t, "{% for x in [1, 2] if x > 5 %}x{% else %}no{% endfor %}", "no")
    check(t, "{% set x = 'outer' %}{% for x in [1] %}{{ x }}{% endfor %}{{ x }}", "1outer")
    check(t, "{% for i in range(2) %}{% for j in range(2) %}{{ loop.depth }}{{ i }}{{ j }} " +
        "{% endfor %}{% endfor %}", "100 101 110 111 ")
    check(t, "{% for x in [1, 2, 3, 4] %}{% if x == 3 %}{% break %}{% endif %}{{ x }}" +
        "{% endfor %}", "12")
    check(t, "{% for x in [1, 2, 3, 4] %}{% if x is even %}{% continue %}{% endif %}{{ x }}" +
        "{% endfor %}", "13")
    check(t, "{% for i in range(3) %}{% set x = i * 2 %}{{ x }}{% endfor %}[{{ x }}]",
        "024[]")
    check(t, "{% for x in [1, 2] %}{% for y in 'ab' %}{{ loop.index }}{% endfor %}" +
        "{{ loop.index }}{% endfor %}", "121122")
    check(t, "{{ loop }}{% for x in [1] %}{{ loop }}{% endfor %}", "<LoopContext 1/1>")
    check_error(t, "{% for x in 42 %}{% endfor %}", "'int' object is not iterable")
    check_error(t, "{% for a, b in [1] %}{% endfor %}", "cannot unpack")
}

@(test)
recursive_loops :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    tree := "{'items': [{'n': 'a', 'c': [{'n': 'b', 'c': []}, {'n': 'c', 'c': " +
        "[{'n': 'd', 'c': []}]}]}, {'n': 'e', 'c': []}]}"
    check(t, "{% for i in items recursive %}<{{ i.n }}{{ loop.depth }}" +
        "{% if i.c %}[{{ loop(i.c) }}]{% endif %}>{% endfor %}",
        "<a1[<b2><c2[<d3>]>]><e1>", tree)
    check(t, "{% for i in items recursive %}{{ loop.depth0 }}{{ loop(i.c) }}{% endfor %}",
        "01120", tree)
    check_error(t, "{% for x in [1] %}{{ loop([]) }}{% endfor %}", "non recursive loop")
}

@(test)
set_and_namespace :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    check(t, "{% set a = 1 %}{% set b, c = 2, 3 %}{{ a }}{{ b }}{{ c }}", "123")
    check(t, "{% set a, b = 'xy' %}{{ b }}{{ a }}", "yx")
    check(t, "{% set x %}Hello {{ 'World' }}{% endset %}[{{ x }}]", "[Hello World]")
    check(t, "{% set x | upper | replace('L', 'l') %}hello{% endset %}{{ x }}", "HEllO")
    check(t, "{% set ns = namespace(found=false, n=0) %}{% for i in [1, 2, 3] %}" +
        "{% set ns.n = ns.n + i %}{% if i == 2 %}{% set ns.found = true %}{% endif %}" +
        "{% endfor %}{{ ns.found }} {{ ns.n }}", "True 6")
    check(t, "{% set ns = namespace({'a': 1}, b=2) %}{{ ns.a }}{{ ns.b }}{{ ns.c }}", "12")
    check(t, "{% set ns = namespace() %}{% set ns.x = 5 %}{{ ns }}", "<Namespace {'x': 5}>")
    check(t, "{% set total = 0 %}{% for i in [1, 2] %}{% set total = total + i %}" +
        "{{ total }}{% endfor %}{{ total }}", "130")
    check_error(t, "{% set d = {} %}{% set d.x = 1 %}", "non-namespace object")
    check_error(t, "{% set a, b = [1, 2, 3] %}", "too many values to unpack (expected 2)")
    check_error(t, "{% set true = 1 %}", "can't assign to 'Const'")
}

@(test)
with_filter_do_raw_autoescape :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    check(t, "{% with a = 1, b = 2 %}{{ a + b }}{% endwith %}[{{ a }}]", "3[]")
    check(t, "{% set a = 5 %}{% with a = 1, b = a %}{{ b }}{% endwith %}", "5")
    check(t, "{% with %}{% set x = 1 %}{{ x }}{% endwith %}[{{ x }}]", "1[]")
    check(t, "{% filter upper %}hello {{ 'x' }}{% endfilter %}", "HELLO X")
    check(t, "{% filter trim | center(7) %}  ab  {% endfilter %}|", "   ab  |")
    check(t, "{% set l = [] %}{% do l.append(1) %}{{ l }}", "[1]")
    check(t, "{% raw %}{{ not }} {% if %}{% endraw %}", "{{ not }} {% if %}")
    check(t, "{%- raw -%}  a  {%- endraw -%}", "a")
    check(t, "{% autoescape true %}{{ '<b>' }}{% endautoescape %}{{ '<b>' }}",
        "&lt;b&gt;<b>")
    check(t, "{% autoescape false %}{{ '<b>' }}{% endautoescape %}{{ '<b>' }}",
        "<b>&lt;b&gt;", options = {autoescape = true})
    check(t, "{# a comment #}x{# multi\nline #}y", "xy")
}

@(test)
macros_and_call_blocks :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    check(t, "{% macro hi(name, greeting='Hello') %}{{ greeting }}, {{ name }}!{% endmacro %}" +
        "{{ hi('Ann') }} {{ hi('Bob', greeting='Hey') }}", "Hello, Ann! Hey, Bob!")
    check(t, "{% macro m(a, b=a * 2) %}{{ a }}{{ b }}{% endmacro %}{{ m(3) }}", "36")
    check(t, "{% macro v() %}{{ varargs }}{{ kwargs }}{% endmacro %}{{ v(1, 2, k=3) }}",
        "(1, 2){'k': 3}")
    check(t, "{% macro m(x) %}[{{ x }}]{% endmacro %}{{ m() }}", "[]")
    check(t, "{% macro list(items) %}<ul>{% for i in items %}<li>{{ caller(i) }}</li>" +
        "{% endfor %}</ul>{% endmacro %}{% call(item) list([1, 2]) %}#{{ item }}{% endcall %}",
        "<ul><li>#1</li><li>#2</li></ul>")
    check(t, "{% macro box() %}<div>{{ caller() }}</div>{% endmacro %}" +
        "{% call box() %}inside{% endcall %}", "<div>inside</div>")
    check(t, "{% macro m(a, b) %}{% endmacro %}{{ m.name }} {{ m.arguments }} " +
        "{{ m.catch_varargs }} {{ m.caller }}", "m ('a', 'b') False False")
    check(t, "{% macro fact(n) %}{% if n <= 1 %}1{% else %}{{ n * fact(n - 1) | int }}" +
        "{% endif %}{% endmacro %}{{ fact(5) }}", "120")
    check(t, "{% macro m() %}<b>{% endmacro %}{{ m() }}", "<b>", options = {autoescape = true})
    check(t, "{% set x = 'outer' %}{% macro m() %}{{ x }}{% endmacro %}{{ m() }}", "outer")
    check(t, "{{ m }}{% macro m() %}{% endmacro %}{{ m }}", "<Macro 'm'>")
    check_error(t, "{% macro m(a) %}{% endmacro %}{{ m(1, 2) }}",
        "macro 'm' takes not more than 1 argument(s)")
    check_error(t, "{% macro m() %}{% endmacro %}{{ m(z=1) }}",
        "macro 'm' takes no keyword argument 'z'")
    check_error(t, "{% macro m() %}{% endmacro %}{% call m() %}x{% endcall %}",
        "macro 'm' takes no keyword argument 'caller'")
    check_error(t, "{% macro m(a) %}{% endmacro %}{{ m(1, a=2) }}",
        "macro 'm' got multiple values for argument 'a'")
}

@(test)
whitespace_control :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    check(t, "a  {{- 'b' -}}  c", "abc")
    check(t, "a\n  {%- if true -%}\n  b\n  {%- endif -%}\n  c", "abc")
    check(t, "{% for x in [1, 2] %}\n{{ x }}\n{% endfor %}\n", "\n1\n\n2\n")
    check(t, "{% for x in [1, 2] %}\n{{ x }}\n{% endfor %}\n", "1\n2\n",
        options = {trim_blocks = true})
    check(t, "<div>\n    {% if true %}\n    yes\n    {% endif %}\n</div>",
        "<div>\n    yes\n</div>", options = {trim_blocks = true, lstrip_blocks = true})
    check(t, "    {%+ if true %}x{% endif %}", "    x", options = {lstrip_blocks = true})
    check(t, "{% if true +%}\nx{% endif %}", "\nx", options = {trim_blocks = true})
    check(t, "  {# c #}\nx", "x", options = {trim_blocks = true, lstrip_blocks = true})
    check(t, "  {{ 'v' }}\n", "  v", options = {trim_blocks = true, lstrip_blocks = true})
    check(t, "a\n", "a")
    check(t, "a\n", "a\n", options = {keep_trailing_newline = true})
    check(t, "a\r\nb", "a\nb")
    check(t, "x {#- c -#} y", "xy")
}
