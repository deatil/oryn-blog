#+feature dynamic-literals
package jinja

import "core:os"
import "core:strings"
import "core:testing"

@(test)
autoescape_interactions :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    on := Options{autoescape = true}
    check(t, "{{ s }}|{{ s|safe }}|{{ s|e }}|{{ s|e|e }}", "&lt;b&gt;|<b>|&lt;b&gt;|&lt;b&gt;",
        "{'s': '<b>'}", on)
    check(t, "{{ '<a>'|safe ~ '<b>' }}", "<a>&lt;b&gt;", "", on)
    check(t, "{{ '<a>'|safe + '<b>' }}", "<a>&lt;b&gt;", "", on)
    check(t, "{{ '<a>' ~ '<b>' }}", "&lt;a&gt;&lt;b&gt;", "", on)
    check(t, "{{ ['<a>', '<b>'|safe]|join(', ') }}", "&lt;a&gt;, <b>", "", on)
    check(t, "{{ ['<a>', '<b>']|join('<br>'|safe) }}", "&lt;a&gt;<br>&lt;b&gt;", "", on)
    check(t, "{% set x %}<i>{% endset %}{{ x }}", "<i>", "", on)
    check(t, "{% macro m(v) %}<p>{{ v }}</p>{% endmacro %}{{ m('<x>') }}", "<p>&lt;x&gt;</p>",
        "", on)
    check(t, "{% macro m() %}<p>{{ caller() }}</p>{% endmacro %}" +
        "{% call m() %}<i>{{ '&' }}</i>{% endcall %}", "<p><i>&amp;</i></p>", "", on)
    check(t, "{{ ('<b>%s</b>'|safe)|format('<i>') }}", "<b>&lt;i&gt;</b>", "", on)
    check(t, "{{ '<b>{}</b>'|safe }}{{ ('<b>{}</b>'|safe).format('&') }}",
        "<b>{}</b><b>&amp;</b>", "", on)
    check(t, "{{ ('<b>'|safe).upper() }}", "<B>", "", on)
    check(t, "{{ ('a'|safe).replace('a', '<') }}", "&lt;", "", on)
    check(t, "{{ 'a<'|replace('<', '>') }}", "a&gt;", "", on)
    check(t, "{% filter upper %}<b>{{ '<i>' }}{% endfilter %}", "<B>&LT;I&GT;", "", on)
    check(t, "{{ x }}", "&lt;&amp;&gt;&#34;&#39;", "{'x': '<&>\"\\''}", on)
    check(t, "{{ [\"<'>\"] }}", "[&#34;&lt;&#39;&gt;&#34;]", "", on)
    check(t, "{% autoescape false %}{{ '<b>'|e }}{{ '<b>' }}{% endautoescape %}",
        "&lt;b&gt;<b>", "", on)
    check(t, "{% trans %}<b>{{ x }}</b>{% endtrans %}", "<b>&lt;i&gt;</b>", "{'x': '<i>'}", on)
}

@(test)
autoescape_by_extension :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    env := create_environment({autoescape_extensions = {".html", ".xml"}})
    defer destroy_environment(&env)
    testing.expect_value(t, add_template(&env, "a.html", "{{ '<' }}"), Error{})
    testing.expect_value(t, add_template(&env, "a.txt", "{{ '<' }}{% include 'a.html' %}"),
        Error{})
    tpl, err := load_template(&env, "a.txt")
    testing.expect_value(t, err.kind, Error_Kind.None)
    out, rerr := render(&tpl)
    testing.expect_value(t, rerr.kind, Error_Kind.None)
    testing.expect_value(t, out, "<&lt;")
}

@(test)
undefined_modes :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    strict := Options{undefined = .Strict}
    check(t, "{{ x is defined }}{{ x|default('d') }}", "Falsed", "", strict)
    check_error(t, "{{ x }}", "'x' is undefined", "", strict)
    check_error(t, "{% if x %}{% endif %}", "'x' is undefined", "", strict)
    check_error(t, "{% for i in x %}{% endfor %}", "'x' is undefined", "", strict)
    check_error(t, "{{ x == 1 }}", "'x' is undefined", "", strict)
    check_error(t, "{{ x ~ 'a' }}", "'x' is undefined", "", strict)
    check_error(t, "{{ x|length }}", "'x' is undefined", "", strict)
    check_error(t, "{{ d.nope }}", "'dict object' has no attribute 'nope'", "{'d': {}}", strict)
    check(t, "[{{ d.nope }}]", "[]", "{'d': {}}")
    check_error(t, "{{ x + 1 }}", "'x' is undefined")
    check_error(t, "{{ x < 1 }}", "'x' is undefined")
    check_error(t, "{{ -x }}", "'x' is undefined")
    chain := Options{undefined = .Chainable}
    check(t, "[{{ a.b.c }}][{{ a['b'].c() }}]", "[][]", "", chain)
    debug := Options{undefined = .Debug}
    check(t, "{{ foo }} {{ d.bar }}", "{{ foo }} {{ no such element: dict object['bar'] }}",
        "{'d': {}}", debug)
}

@(test)
syntax_errors_name_the_line :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    check_error(t, "a\n{{ x", "unexpected end of template, expected 'end of print statement'",
        line = 2)
    check_error(t, "{% if x %}\nopen", "Unexpected end of template. Jinja was looking for the " +
        "following tags: 'elif' or 'else' or 'endif'. The innermost block that needs to be " +
        "closed is 'if'.", line = 2)
    check_error(t, "\n\n{% while x %}", "Encountered unknown tag 'while'.", line = 3)
    check_error(t, "{% for x in y %}{% endif %}", "Encountered unknown tag 'endif'. Jinja was " +
        "looking for the following tags: 'endfor' or 'else'. The innermost block that needs " +
        "to be closed is 'for'.")
    check_error(t, "{% if a %}{% for x in y %}{% endif %}", "You probably made a nesting " +
        "mistake. Jinja is expecting this tag, but currently looking for 'endfor' or 'else'.")
    check_error(t, "{{ 1 + }}", "unexpected 'end of print statement'")
    check_error(t, "{{ )", "unexpected ')'")
    check_error(t, "{{ a b }}", "expected token 'end of print statement', got 'b'")
    check_error(t, "{% for %}", "Expected an expression, got 'end of statement block'")
    check_error(t, "{# open", "Missing end of comment tag")
    check_error(t, "{{ 'abc }}", "unexpected end of string")
    check_error(t, "{{ a | }}", "expected token 'name', got 'end of print statement'")
    check_error(t, "{% break %}", "'break' outside of a loop")
    check_error(t, "{% macro m(a=1, b) %}{% endmacro %}", "non-default argument follows")
    check_error(t, "{% block a %}{% endblock b %}", "mismatching name of block")
    check_error(t, "{% raw %}x", "Missing end of raw directive")
    check_error(t, "{% call m %}{% endcall %}", "expected call")
    check_error(t, "{{ 'a' @ 'b' }}", "unexpected char '@'")
    check_error(t, "{% trans %}{% if x %}{% endif %}{% endtrans %}",
        "control structures in translatable sections are not allowed")
}

@(test)
runtime_errors_name_template_and_line :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    check_error(t, "line1\nline2 {{ 1 // 0 }}", "integer division", line = 2)
    check_error(t, "\n{{ 'x'|nosuch }}", "No filter named 'nosuch'.", line = 2)
    templates := map[string]string{"inner.html" = "ok\n\n{{ boom.x }}"}
    _, err := run("{% include 'inner.html' %}", templates = templates)
    testing.expect_value(t, err.template, "inner.html")
    testing.expect_value(t, err.line, 3)
    testing.expect_value(t, err.excerpt, "{{ boom.x }}")
    testing.expect_value(t, err.kind, Error_Kind.Undefined)
    report := format_error(err)
    testing.expect(t, strings.has_prefix(report, "-- UNDEFINED VALUE ---"))
    testing.expect(t, strings.contains(report, "inner.html:3\n\n'boom' is undefined\n"))
    testing.expect(t, strings.contains(report, "\n3| {{ boom.x }}\n"))
    testing.expect(t, strings.contains(report, "Hint: "))
    _, err = run("{{ uper }}", "{'upper': 1}", {undefined = .Strict})
    testing.expect_value(t, err.hint, "Did you mean 'upper'?")
    _, err = run("{{ 'a'|uppr }}")
    testing.expect_value(t, err.hint, "Did you mean the filter 'upper'?")
    _, err = run("{% endfro %}")
    testing.expect_value(t, err.hint, "Did you mean {% endfor %}?")
    _, err = run("{{ 1 }}\n{% if %}")
    testing.expect_value(t, err.kind, Error_Kind.Syntax)
    testing.expect_value(t, err.excerpt, "{% if %}")
}

@(test)
limits_stop_runaway_templates :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    check_error(t, "{% macro r() %}{{ r() }}{% endmacro %}{{ r() }}", "recursion limit of 20",
        options = {max_recursion = 20})
    check_error(t, "{% for i in range(100) %}{% endfor %}", "iteration limit",
        options = {max_iterations = 50})
    check_error(t, "{{ range(1000) }}", "exceeds the iteration limit", options = {
        max_iterations = 100})
    check_error(t, "{% for i in range(50) %}xxxxxxxxxx{% endfor %}", "output limit of 100",
        options = {max_output = 100})
    templates := map[string]string{"self.html" = "{% include 'self.html' %}"}
    check_error(t, "{% include 'self.html' %}", "recursion limit", templates = templates)
    check_error(t, "{% for x in items recursive %}{{ loop(items) }}{% endfor %}",
        "recursion limit", "{'items': [1]}")
}

@(test)
i18n_trans_tag :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    check(t, "{% trans %}Hello {{ user }}!{% endtrans %}", "Hello Ann!", "{'user': 'Ann'}")
    check(t, "{% trans name=user|upper %}Hi {{ name }}{% endtrans %}", "Hi ANN",
        "{'user': 'Ann'}")
    check(t, "{% trans count=n %}{{ count }} item{% pluralize %}{{ count }} items{% endtrans %}",
        "1 item", "{'n': 1}")
    check(t, "{% trans count=n %}{{ count }} item{% pluralize %}{{ count }} items{% endtrans %}",
        "3 items", "{'n': 3}")
    check(t, "{% trans %}100% sure{% endtrans %}", "100% sure")
    check(t, "{% trans x=1 %}100% {{ x }}{% endtrans %}", "100% 1")
    check(t, "{% trans trimmed %}\n  Hello\n    world  {% endtrans %}", "Hello world")
    check(t, "{% trans %}{{ a }}{% pluralize %}{{ a }}s{% endtrans %}", "2s", "{'a': 2}")
}

@(test)
host_api_values_filters_tests_globals :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    env := create_environment({autoescape = true})
    defer destroy_environment(&env)
    shout :: proc(c: ^Call) -> Value {
        times, _ := arg_int(c, 1, "times", 1)
        return strings.repeat(to_upper(to_string(c.args[0])), int(times))
    }
    add_filter(&env, "shout", shout)
    long :: proc(c: ^Call) -> Value { return length(c.args[0]) > 3 }
    add_test(&env, "long", long)
    add_global(&env, "site", str("Guidedog"))
    greet :: proc(c: ^Call) -> Value {
        if len(c.args) == 0 do return fail(c, "greet needs a name")
        return markup(strings.concatenate({"<b>", to_string(c.args[0]), "</b>"}))
    }
    add_function(&env, "greet", greet)
    ctx := dict()
    set(ctx, "name", str("<ann>"))
    set(ctx, "n", integer(3))
    set(ctx, "f", float(1.5))
    set(ctx, "ok", boolean(true))
    set(ctx, "items", list(integer(1), str("x"), none()))
    set(ctx, "html", markup("<br>"))
    set(ctx, "pair", tuple(integer(1), integer(2)))
    tpl, err := parse_template(&env, "page.html",
        "{{ name|shout(2) }} {{ 'abcd' is long }} {{ site }} {{ greet('x') }} {{ n }} {{ f }} " +
        "{{ ok }} {{ items }} {{ html }} {{ pair }}")
    testing.expect_value(t, err.kind, Error_Kind.None)
    out, rerr := render(&tpl, ctx)
    testing.expect_value(t, rerr.kind, Error_Kind.None)
    testing.expect_value(t, out, "&lt;ANN&gt;&lt;ANN&gt; True Guidedog <b>x</b> 3 1.5 True " +
        "[1, &#39;x&#39;, None] <br> (1, 2)")
    tpl, _ = parse_template(&env, "bad.html", "{{ greet() }}")
    _, rerr = render(&tpl, ctx)
    testing.expect_value(t, rerr.message, "greet needs a name")
    testing.expect_value(t, rerr.template, "bad.html")
    testing.expect_value(t, get(ctx, "n"), Value(i64(3)))
    testing.expect_value(t, length(get(ctx, "items")), 3)
    v, eerr := evaluate(&env, "n * 2 + items|length", ctx)
    testing.expect_value(t, eerr.kind, Error_Kind.None)
    testing.expect_value(t, v, Value(i64(9)))
}

@(test)
loaders :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    sources := map[string]string{"base.html" = "B[{% block x %}{% endblock %}]",
        "page.html" = "{% extends 'base.html' %}{% block x %}{{ v }}{% endblock %}"}
    env := create_environment({loader = memory_loader(&sources)})
    tpl, err := load_template(&env, "page.html")
    testing.expect_value(t, err.kind, Error_Kind.None)
    ctx := dict()
    set(ctx, "v", integer(7))
    out, _ := render(&tpl, ctx)
    testing.expect_value(t, out, "B[7]")
    sources["base.html"] = "changed"
    out, _ = render(&tpl, ctx)
    testing.expect_value(t, out, "B[7]")
    clear_cache(&env)
    tpl, _ = load_template(&env, "page.html")
    out, _ = render(&tpl, ctx)
    testing.expect_value(t, out, "changed")
    _, err = load_template(&env, "nope.html")
    testing.expect_value(t, err.kind, Error_Kind.Not_Found)
    destroy_environment(&env)

    root, derr := os.make_directory_temp("", "jinja-loader-*", context.allocator)
    testing.expect(t, derr == nil)
    defer os.remove_all(root)
    first := strings.concatenate({root, "/first"})
    second := strings.concatenate({root, "/second"})
    testing.expect(t, os.make_directory_all(strings.concatenate({first, "/sub"})) == nil)
    testing.expect(t, os.make_directory_all(second) == nil)
    write :: proc(path, text: string) -> bool { return os.write_entire_file(path, text) == nil }
    testing.expect(t, write(strings.concatenate({first, "/a.html"}), "first-a"))
    testing.expect(t, write(strings.concatenate({second, "/a.html"}), "second-a"))
    testing.expect(t, write(strings.concatenate({second, "/b.html"}),
        "b+{% include 'sub/c.html' %}"))
    testing.expect(t, write(strings.concatenate({first, "/sub/c.html"}), "c"))
    testing.expect(t, write(strings.concatenate({root, "/secret.html"}), "secret"))
    fenv := create_environment({loader = filesystem_loader({first, second})})
    defer destroy_environment(&fenv)
    wants := map[string]string{"a.html" = "first-a", "b.html" = "b+c",
        "./sub/c.html" = "c", "/sub/c.html" = "c"}
    for name, want in wants {
        ft, ferr := load_template(&fenv, name)
        testing.expectf(t, ferr.kind == .None, "%s: %v", name, ferr)
        fout, _ := render(&ft)
        testing.expect_value(t, fout, want)
    }
    for name in ([]string{"../secret.html", "sub/../../secret.html", "missing.html"}) {
        _, ferr := load_template(&fenv, name)
        testing.expect_value(t, ferr.kind, Error_Kind.Not_Found)
    }
}

@(test)
rendering_in_an_arena_leaks_nothing :: proc(t: ^testing.T) {
    env := create_environment({autoescape = true})
    defer destroy_environment(&env)
    testing.expect_value(t, add_template(&env, "m.html",
        "{% macro m(x) %}<{{ x }}>{% endmacro %}"), Error{})
    tpl, err := parse_template(&env, "t.html", "{% from 'm.html' import m %}" +
        "{% for i in range(3) %}{{ m(i) }}{{ [i]|tojson }}{% endfor %}{{ 1 // 0 }}")
    testing.expect_value(t, err.kind, Error_Kind.None)
    _, rerr := render(&tpl)
    testing.expect_value(t, rerr.kind, Error_Kind.Runtime)
    destroy_error(rerr)
    tpl, _ = parse_template(&env, "t2.html", "{% for i in range(3) %}{{ i }}{% endfor %}")
    out, _ := render(&tpl)
    testing.expect_value(t, out, "012")
    delete(out)
}
