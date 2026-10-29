#+feature dynamic-literals
package jinja

import "core:strings"
import "core:testing"

@(private="file")
pathto :: proc(c: ^Call) -> Value {
    target := to_string(arg(c, 0, "otheruri"))
    if truthy(arg(c, 1, "resource", false)) do return strings.concatenate({"../", target})
    return strings.concatenate({target, ".html"})
}

@(private="file")
tobool :: proc(c: ^Call) -> Value {
    v := arg(c, 0, "value")
    if text, ok := v.(string); ok do return to_lower(text) == "true" || text == "1"
    return truthy(v)
}

@(test)
sphinx_like_theme_renders :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    sources := map[string]string {
        "basic/layout.html" = `{%- macro relbar() %}
<div class="related"><ul>
{%- for rellink in rellinks|reverse %}
<li><a href="{{ pathto(rellink[0]) }}" title="{{ rellink[1]|striptags|e
    }}">{{ rellink[3] }}</a>{{ reldelim2 }}</li>
{%- endfor %}
{%- block rootrellink %}<li><a href="{{
    pathto(root_doc) }}">{{ shorttitle|e }}</a></li>{% endblock %}
</ul></div>
{%- endmacro %}
<!DOCTYPE html>
<html lang="{{ language }}">
<head><title>{{ title|striptags|e }}{{ titlesuffix }}</title>
{%- for css in css_files %}
<link rel="stylesheet" href="{{ pathto(css, 1) }}" />
{%- endfor %}
{%- block extrahead %}{% endblock %}
</head>
<body>
{%- block relbar1 %}{{ relbar() }}{% endblock %}
<div class="body">{% block body %}{% endblock %}</div>
{%- if theme_show_footer|tobool %}
<footer>{% trans copyright=copyright|e %}&copy; {{ copyright }}.{% endtrans %}</footer>
{%- endif %}
</body></html>`,
        "alabaster/layout.html" = `{%- extends "basic/layout.html" %}
{%- block extrahead %}
{{ super() }}<meta name="theme" content="alabaster" />
{%- endblock %}
{%- block rootrellink %}<li>{{ _('Home') }}</li>{% endblock %}`,
        "page.html" = `{%- extends "alabaster/layout.html" %}
{%- block body %}{{ body }}{% endblock %}`,
    }
    env := create_environment({autoescape = true, loader = memory_loader(&sources),
        trim_blocks = false})
    defer destroy_environment(&env)
    add_function(&env, "pathto", pathto)
    add_filter(&env, "tobool", tobool)
    ctx := dict()
    set(ctx, "language", str("en"))
    set(ctx, "title", str("Intro <em>here</em>"))
    set(ctx, "titlesuffix", str(" &mdash; Docs"))
    set(ctx, "css_files", list(str("_static/a.css"), str("_static/b.css")))
    set(ctx, "rellinks", list(tuple(str("genindex"), str("General Index"), str("I"),
        str("index")), tuple(str("next"), str("<b>Next</b>"), str("N"), str("next"))))
    set(ctx, "reldelim2", str(" |"))
    set(ctx, "root_doc", str("index"))
    set(ctx, "shorttitle", str("Docs"))
    set(ctx, "body", markup("<p>Hello</p>"))
    set(ctx, "theme_show_footer", str("true"))
    set(ctx, "copyright", str("2026, A & B"))
    tpl, err := load_template(&env, "page.html")
    testing.expectf(t, err.kind == .None, "%s", format_error(err))
    out, rerr := render(&tpl, ctx)
    testing.expectf(t, rerr.kind == .None, "%s", format_error(rerr))
    want := `
<!DOCTYPE html>
<html lang="en">
<head><title>Intro here &amp;mdash; Docs</title>
<link rel="stylesheet" href="../_static/a.css" />
<link rel="stylesheet" href="../_static/b.css" />
<meta name="theme" content="alabaster" />
</head>
<body>
<div class="related"><ul>
<li><a href="next.html" title="Next">next</a> |</li>
<li><a href="genindex.html" title="General Index">index</a> |</li><li>Home</li>
</ul></div>
<div class="body"><p>Hello</p></div>
<footer>&copy; 2026, A &amp; B.</footer>
</body></html>`
    testing.expectf(t, out == want, "got:\n%s", out)
}

@(test)
inheritance_edge_cases :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    templates := map[string]string {
        "base.html" = "[{% block a %}base-a{% endblock %}|{% block b %}base-b{% endblock %}]",
        "m.html" = "{% macro hi() %}hi{% endmacro %}",
        "part.html" = "PART",
        "l1.html" = "{% extends 'base.html' %}{% block a %}l1({{ super() }}){% endblock %}",
        "l2.html" = "{% extends 'l1.html' %}{% block a %}l2({{ super() }}){% endblock %}" +
            "{% block b %}{{ self.a() }}{% endblock %}",
    }
    check(t, "{% extends 'base.html' %}{% include 'part.html' %}", "[base-a|base-b]", "", {},
        templates)
    check(t, "before{% extends 'base.html' %}", "before[base-a|base-b]", "", {}, templates)
    check(t, "{% extends 'base.html' %}{% import 'm.html' as m %}{% block a %}{{ m.hi() }}" +
        "{% endblock %}", "[hi|base-b]", "", {}, templates)
    check(t, "{% extends 'base.html' %}{% macro x() %}X{% endmacro %}{% block b %}{{ x() }}" +
        "{% endblock %}", "[base-a|X]", "", {}, templates)
    check(t, "{% extends 'l2.html' %}{% block a %}l3({{ super() }}){% endblock %}",
        "[l3(l2(l1(base-a)))|l3(l2(l1(base-a)))]", "", {}, templates)
    check(t, "{% extends 'base.html' %}{% set x %}{% include 'part.html' %}{% endset %}" +
        "{% block a %}{{ x }}{% endblock %}", "[PART|base-b]", "", {}, templates)
    check(t, "{% extends 'base.html' %}{% block b %}{% block inner %}in{% endblock %}" +
        "{% endblock %}", "[base-a|in]", "", {}, templates)
}

@(test)
macros_imported_keep_their_template :: proc(t: ^testing.T) {
    context.allocator = context.temp_allocator
    templates := map[string]string {
        "forms.html" = "{% macro input(name, value='', type='text') -%}\n" +
            "<input type=\"{{ type }}\" name=\"{{ name }}\" value=\"{{ value|e }}\">\n" +
            "{%- endmacro %}{% macro field(label) %}<label>{{ label }}{{ caller() }}</label>" +
            "{% endmacro %}",
        "err.html" = "{% macro bad() %}\n\n{{ 1 // 0 }}{% endmacro %}",
    }
    check(t, "{% import 'forms.html' as f %}{{ f.input('q', '<x>') }}",
        "<input type=\"text\" name=\"q\" value=\"&lt;x&gt;\">", "", {}, templates)
    check(t, "{% from 'forms.html' import field, input %}{% call field('L') %}" +
        "{{ input('n', type='password') }}{% endcall %}",
        "<label>L<input type=\"password\" name=\"n\" value=\"\"></label>", "", {}, templates)
    _, err := run("{% from 'err.html' import bad %}\n{{ bad() }}", templates = templates)
    testing.expect_value(t, err.template, "err.html")
    testing.expect_value(t, err.line, 3)
}
