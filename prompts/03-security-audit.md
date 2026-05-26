# Security audit — language-aware taint analysis (codebase-memory-mcp backend)
# Budget: <=12k tokens total context

## Preflight

1. **`get_graph_schema`** — confirm Route + Function + HTTP_CALLS counts > 0. If 0 routes, this is a library — focus on public API surface instead.
2. **`get_architecture`** — pick `languages` and `entry_points` to scope the audit.

## Taint sources (treat output as untrusted)

| Language / framework | Sources |
|---|---|
| PHP / Symfony / Laravel | `$_GET`, `$_POST`, `$_COOKIE`, `Request->get()`, `Request->query->get()`, `FormRequest`, route params |
| Node / Express / Next | `req.query.*`, `req.body.*`, `req.params.*`, `req.headers.*`, `req.cookies.*` |
| Python / Django | `request.GET`, `request.POST`, `request.COOKIES`, `request.FILES`, `request.headers`, URL kwargs |
| Python / Flask / FastAPI | `request.args`, `request.form`, `request.json`, `request.values`, `request.cookies` |
| Go (net/http, gin, echo, fiber) | `*http.Request`, `c.Query/Param/PostForm/BindJSON`, gRPC `proto.Message` |
| Rust (actix, axum) | `web::Path<T>`, `web::Query<T>`, `web::Json<T>`, `Extract::extract` |

## Taint sinks (dangerous if source flows here unsanitized)

| Language / framework | Sinks |
|---|---|
| PHP / Symfony | Twig `\|raw`, `Twig\Environment::createTemplate`, PDO query/execute with concatenated SQL, `shell_exec`, `passthru`, `system`, `eval`, `unserialize`, `file_get_contents($userUrl)`, `header("Location: …")` w/ user input |
| Node / Express | `child_process` shell APIs (exec / execSync / spawn with shell:true), `eval`, `vm.runInNewContext`, `res.send/write` w/ unencoded HTML, template-literal SQL in `db.query`, `fs.*` w/ user path, `res.redirect(userUrl)` |
| Python / Django | `QuerySet.raw()`, `.extra()`, `RawSQL()`, `cursor.execute(f"...{user}...")`, `mark_safe()`, `SafeString(...)`, `os.system`, `subprocess.call(shell=True)`, `pickle.loads`, `HttpResponseRedirect(user_url)` |
| Go | `db.Query/QueryContext` w/ concat strings, GORM `Raw()/Exec()/Where(stringFragment)`, `os/exec.Command("sh", "-c", user)`, `text/template` bypass, `http.Redirect(userUrl)` |
| Rust | `diesel::sql_query(format!())`, `sqlx::query(&format!())`, `std::process::Command::new("sh").arg("-c").arg(user)`, hand-built HTML via `format!()` into `HttpResponse::body()` |

## Safe sinks (do NOT flag if source passes through)

- PHP: Doctrine parameterized queries, Twig auto-escape, `htmlspecialchars`, `filter_var`
- Node: `pg`/`mysql2` prepared statements, `helmet`, `xss-filters`, `child_process.execFile(bin, [args])` (no shell)
- Django: parameterized ORM, auto-escaped templates (no `mark_safe`), `urllib.parse.quote`
- Go: prepared statements `db.Query("... ?", arg)`, `html/template`, `os/exec.Command(bin, arg1, arg2)` (no shell)
- Rust: Diesel typed query builder, `sqlx::query!()` macro, `Command::new(bin).arg(arg)` (no shell)

## Procedure

1. **`search_graph(label="Route")`** — enumerate every REST route as `method path -> handler`.
2. **`query_graph("MATCH (a)-[r:HTTP_CALLS]->(b) RETURN a.name, b.name, r.url_path LIMIT 50")`** — outbound cross-service calls (potential SSRF surface).
3. For each handler: **`trace_path(function_name=<handler qname>, direction="outbound", depth=4)`**. Walk to leaves.
4. For each path that touches a known sink: **`get_code_snippet(qualified_name=<qname>)`** and verify a sanitizer is on the path.
5. Missing-auth detection (adjust auth function name per project):
   ```cypher
   MATCH (r:Route)-[:HANDLES]->(f:Function)
   WHERE NOT (f)-[:CALLS*1..3]->(:Function {name: 'isAuthenticated'})
   RETURN r.method, r.path, f.qualified_name LIMIT 50
   ```
6. Cross-cutting checks:
   - Dead code with auth checks (orphan defenses): `search_graph(label="Function", max_degree=0, exclude_entry_points=true, name_pattern=".*(auth|verify|check).*")`
   - High-fan-in functions handling user input (broad blast radius): `search_graph(label="Function", min_degree=20, relationship="CALLS", direction="inbound")`
7. Report per finding: route → handler → sink chain → sanitizer present (yes/no/unknown) → CWE-id (CWE-89 SQLi, CWE-79 XSS, CWE-78 OS-Cmd, CWE-22 path traversal, CWE-918 SSRF, CWE-502 deserialization, CWE-862 missing-auth, CWE-352 CSRF).
