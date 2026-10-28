#+feature dynamic-literals
package jinja

import "core:strings"
import "core:testing"

@(test)
builtin_tests :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    check(t, "{{ x is defined }} {{ y is defined }} {{ y is undefined }} {{ none is none }}",
        "True False True True", "{'x': 1}")
    check(t, "{{ 3 is odd }} {{ 4 is even }} {{ 9 is divisibleby 3 }} {{ 9 is divisibleby(2) }}",
        "True True True False")
    check(t, "{{ 1 is number }} {{ 1.5 is float }} {{ 1 is integer }} {{ true is integer }}",
        "True True True False")
    check(t, "{{ true is boolean }} {{ 1 is boolean }} {{ true is true }} {{ 1 is true }}",
        "True False True False")
    check(t, "{{ false is false }} {{ 0 is false }} {{ 'a' is string }} {{ 1 is string }}",
        "True False True False")
    check(t, "{{ {} is mapping }} {{ [] is mapping }} {{ [] is sequence }} {{ 'x' is sequence }}",
        "True False True True")
    check(t, "{{ [] is iterable }} {{ 3 is iterable }} " +
        "{{ range is callable }} {{ 1 is callable }}",
        "True False True False")
    check(t, "{{ 'abc' is lower }} {{ 'aBc' is lower }} {{ 'ABC' is upper }} {{ '1' is upper }}",
        "True False True False")
    check(t, "{{ 1 is eq 1 }} {{ 1 is equalto 2 }} " +
        "{{ 1 is ne 2 }} {{ 1 is lt 2 }} {{ 2 is le 2 }}",
        "True False True True True")
    check(t, "{{ 3 is gt 2 }} {{ 3 is greaterthan 4 }} {{ 3 is ge 3 }} {{ 1 is lessthan 0 }}",
        "True False True False")
    check(t, "{{ 2 is in [1, 2] }} {{ 'x' is in 'abc' }} {{ 'upper' is filter }} " +
        "{{ 'odd' is test }} {{ 'nope' is filter }}", "True False True True False")
    check(t, "{{ '<b>'|safe is escaped }} {{ '<b>' is escaped }}", "True False")
    check(t, "{% set a = [1] %}{% set b = a %}{{ a is sameas b }} {{ a is sameas [1] }} " +
        "{{ none is sameas none }} {{ 1 is sameas true }}", "True False True False")
    check(t, "{{ x is not defined }} {{ 3 is not even }} {{ not 3 is even }}",
        "True True True")
    check(t, "{{ 1 if x is defined else 2 }}", "2")
    check_error(t, "{{ 1 is nosuchtest }}", "No test named 'nosuchtest'.")
}

@(test)
builtin_globals :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    check(t, "{{ range(3)|list }} {{ range(2, 5)|list }} {{ range(10, 0, -3)|list }} " +
        "{{ range(0)|list }}", "[0, 1, 2] [2, 3, 4] [10, 7, 4, 1] []")
    check(t, "{{ dict(a=1) }} {{ dict([('b', 2)]) }} {{ dict({'c': 3}, d=4) }}",
        "{'a': 1} {'b': 2} {'c': 3, 'd': 4}")
    check(t, "{% set c = cycler('a', 'b') %}{{ c.next() }}{{ c.next() }}{{ c.next() }}" +
        "{{ c.current }}{% do c.reset() %}{{ c.next() }}", "ababa")
    check(t, "{% set j = joiner('|') %}{% for x in 'abc' %}{{ j() }}{{ x }}{% endfor %}",
        "a|b|c")
    check(t, "{% set j = joiner() %}{{ j() }}{{ j() }}{{ j() }}", ", , ")
    check(t, "{{ namespace(a=1).a }}", "1")
    check(t, "{{ gettext('Hello') }} {{ _('Hi') }} {{ ngettext('%(num)d apple', " +
        "'%(num)d apples', 3) }}", "Hello Hi %(num)d apples")
    check_error(t, "{{ range(1, 2, 0) }}", "range() arg 3 must not be zero")
    check_error(t, "{{ range('a') }}", "'str' object cannot be interpreted as an integer")
}

@(test)
lipsum_is_deterministic :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    a, err := run("{{ lipsum(2) }}")
    testing.expect_value(t, err.kind, Error_Kind.None)
    b, _ := run("{{ lipsum(2) }}")
    testing.expect_value(t, a, b)
    testing.expect(t, strings.has_prefix(a, "<p>") && strings.count(a, "<p>") == 2)
    c, _ := run("{{ lipsum(1, false, 5, 5) }}")
    testing.expect_value(t, len(python_split(c)), 5)
    testing.expect(t, strings.has_suffix(c, "."))
    d, _ := run("{{ lipsum(2) }}", options = {random_seed = 7})
    testing.expect(t, a != d)
}

@(test)
inheritance :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    templates := map[string]string {
        "base.html" = "<title>{% block title %}Base{% endblock %}</title>" +
            "<body>{% block body %}{% block inner %}I{% endblock %}{% endblock body %}</body>",
        "mid.html" = "{% extends 'base.html' %}{% block title %}Mid-{{ super() }}{% endblock %}" +
            "{% block inner %}M{% endblock %}",
        "req.html" = "{% block needed required %}{# note #}  {% endblock %}",
        "self.html" = "{% block a %}A{% endblock %}|{{ self.a() }}",
        "scoped.html" = "{% for i in [1, 2] %}{% block item scoped %}{{ i }}{% endblock %}" +
            "{% endfor %}",
        "unscoped.html" = "{% for i in [1, 2] %}{% block item %}[{{ i }}]{% endblock %}" +
            "{% endfor %}",
        "uses_var.html" = "{% block b %}{{ title }}{% endblock %}",
    }
    check(t, "{% extends 'base.html' %}", "<title>Base</title><body>I</body>", "", {}, templates)
    check(t, "{% extends 'mid.html' %}{% block title %}Top-{{ super() }}{% endblock %}",
        "<title>Top-Mid-Base</title><body>M</body>", "", {}, templates)
    check(t, "{% extends 'mid.html' %}{% block body %}B{{ super() }}{% endblock %}",
        "<title>Mid-Base</title><body>BM</body>", "", {}, templates)
    check(t, "{% extends 'base.html' %}ignored{% block title %}T{% endblock %}ignored",
        "<title>T</title><body>I</body>", "", {}, templates)
    check(t, "{% extends 'req.html' %}{% block needed %}ok{% endblock %}", "ok", "", {},
        templates)
    check_error(t, "{% extends 'req.html' %}", "Required block 'needed' not found", "", {},
        templates)
    check(t, "{% extends 'self.html' %}{% block a %}B{% endblock %}", "B|B", "", {}, templates)
    check(t, "{% extends 'scoped.html' %}{% block item %}<{{ i }}>{% endblock %}",
        "<1><2>", "", {}, templates)
    check(t, "{% extends 'unscoped.html' %}", "[][]", "", {}, templates)
    check(t, "{% extends 'uses_var.html' %}{% set title = 'T' %}", "T", "", {}, templates)
    check(t, "{% extends name %}", "<title>Base</title><body>I</body>", "{'name': 'base.html'}",
        {}, templates)
    check(t, "{% if false %}{% extends 'mid.html' %}{% endif %}x", "x", "", {}, templates)
    check(t, "{% extends ['nope.html', 'base.html'] %}", "<title>Base</title><body>I</body>",
        "", {}, templates)
    check_error(t, "{% extends 'nope.html' %}", "template 'nope.html' not found", "", {},
        templates)
    check_error(t, "{% extends 'base.html' %}{% extends 'base.html' %}",
        "extended multiple times", "", {}, templates)
    check_error(t, "{% block a %}{{ super() }}{% endblock %}", "no parent block called 'a'")
    check_error(t, "{% block a %}{% endblock %}{% block a %}{% endblock %}",
        "block 'a' defined twice")
}

@(test)
include_and_import :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    templates := map[string]string {
        "part.html" = "[{{ name }}]",
        "loopvar.html" = "<{{ i }}>",
        "setter.html" = "{% set leaked = 1 %}",
        "macros.html" = "{% macro hi(n) %}Hi {{ n }}{% endmacro %}{% set version = 2 %}" +
            "{% set _private = 3 %}{% macro uses_ctx() %}{{ name }}{% endmacro %}",
        "child.html" = "{% extends 'layout.html' %}{% block c %}child{% endblock %}",
        "layout.html" = "L({% block c %}{% endblock %})",
    }
    check(t, "{% include 'part.html' %}", "[x]", "{'name': 'x'}", {}, templates)
    check(t, "{% include 'part.html' without context %}", "[]", "{'name': 'x'}", {}, templates)
    check(t, "{% for i in [1, 2] %}{% include 'loopvar.html' %}{% endfor %}", "<1><2>", "", {},
        templates)
    check(t, "{% include 'setter.html' %}[{{ leaked }}]", "[]", "", {}, templates)
    check(t, "{% include 'missing.html' ignore missing %}ok", "ok", "", {}, templates)
    check(t, "{% include ['missing.html', 'part.html'] %}", "[y]", "{'name': 'y'}", {},
        templates)
    check(t, "{% include 'child.html' %}", "L(child)", "", {}, templates)
    check_error(t, "{% include 'missing.html' %}", "template 'missing.html' not found", "",
        {}, templates)
    check_error(t, "{% include ['a.html', 'b.html'] %}",
        "none of the templates given were found: a.html, b.html")
    check(t, "{% import 'macros.html' as m %}{{ m.hi('Ann') }} {{ m.version }} [{{ m._private }}]",
        "Hi Ann 2 []", "", {}, templates)
    check(t, "{% from 'macros.html' import hi, version as v %}{{ hi('Bo') }}{{ v }}", "Hi Bo2",
        "", {}, templates)
    check(t, "{% from 'macros.html' import uses_ctx %}[{{ uses_ctx() }}]", "[]",
        "{'name': 'n'}", {}, templates)
    check(t, "{% from 'macros.html' import uses_ctx with context %}[{{ uses_ctx() }}]", "[n]",
        "{'name': 'n'}", {}, templates)
    check(t, "{% import 'macros.html' as m with context %}{{ m.uses_ctx() }}", "n",
        "{'name': 'n'}", {}, templates)
    check_error(t, "{% from 'macros.html' import nothing %}{{ nothing() }}",
        "does not export the requested name 'nothing'", "", {}, templates)
    check_error(t, "{% from 'macros.html' import _private %}",
        "names starting with an underline can not be imported", "", {}, templates)
    check(t, "{% import 'macros.html' as m %}{{ m }}", "<TemplateModule 'macros.html'>", "", {},
        templates)
}
