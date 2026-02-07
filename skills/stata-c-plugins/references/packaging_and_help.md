# Stata Package Structure and Distribution

## Required Files for net install

### stata.toc (Table of Contents)

```
v 3
d packagename - Short description of the package
d Author Name, Institution
d Distribution-Date: YYYYMMDD
p packagename
```

- Line 1: `v 3` (version)
- `d` lines: description, author, date
- `p packagename`: references `packagename.pkg`

### packagename.pkg (Package Manifest)

```
v 3
d packagename: One-line description
d
d Author Name, Institution
d email@example.com
d
d Distribution-Date: YYYYMMDD
d
f packagename.ado
f packagename_method1.ado
f packagename.sthlp
f myplugin.darwin-arm64.plugin
f myplugin.darwin-x86_64.plugin
f myplugin.linux-x86_64.plugin
f myplugin.windows-x86_64.plugin
```

- `f` lines list every file to install
- Files install to the user's PLUS ado directory
- Plugin files must be listed explicitly (all platforms)
- Users get all platform binaries; Stata loads the right one at runtime

### Installation Command

```stata
net install packagename, from("https://raw.githubusercontent.com/user/repo/main") replace
```

The `from()` URL must point to a directory containing `stata.toc`.

## Help File (.sthlp) Template

```smcl
{smcl}
{* *! version 1.0.0  DDmonYYYY}{...}
{viewerjumpto "Syntax" "packagename##syntax"}{...}
{viewerjumpto "Description" "packagename##description"}{...}
{viewerjumpto "Options" "packagename##options"}{...}
{viewerjumpto "Examples" "packagename##examples"}{...}
{viewerjumpto "Stored results" "packagename##results"}{...}

{title:Title}

{phang}
{bf:packagename} {hline 2} Short description of what the command does

{marker syntax}{...}
{title:Syntax}

{p 8 17 2}
{cmdab:packagename}
{depvar} {indepvars}
{ifin}
{cmd:,} {opt gen:erate(newvar)} [{it:options}]

{synoptset 25 tabbed}{...}
{synopthdr}
{synoptline}
{syntab:Required}
{synopt:{opt gen:erate(newvar)}}name of new variable to create{p_end}

{syntab:Method}
{synopt:{opt m:ethod(string)}}method name; default is {bf:default}{p_end}
{synopt:{opt q:uantile(#)}}target quantile; default is 0.5{p_end}

{syntab:Other}
{synopt:{opt seed(#)}}random seed; default is 12345{p_end}
{synopt:{opt replace}}replace existing variable{p_end}
{synoptline}

{marker description}{...}
{title:Description}

{pstd}
{cmd:packagename} does X based on Y.

{marker options}{...}
{title:Options}

{phang}
{opt method(string)} specifies the method. Options are:
{phang2}{bf:method1} - Description{p_end}
{phang2}{bf:method2} - Description{p_end}

{marker examples}{...}
{title:Examples}

{pstd}Setup{p_end}
{phang2}{cmd:. sysuse auto, clear}{p_end}

{pstd}Basic usage{p_end}
{phang2}{cmd:. packagename price mpg weight, gen(price_imputed)}{p_end}

{marker results}{...}
{title:Stored results}

{synoptset 20 tabbed}{...}
{p2col 5 20 24 2: Scalars}{p_end}
{synopt:{cmd:r(N)}}number of observations{p_end}
{synopt:{cmd:r(seed)}}random seed used{p_end}

{p2col 5 20 24 2: Macros}{p_end}
{synopt:{cmd:r(method)}}method used{p_end}
```

### SMCL Formatting Cheat Sheet

- `{txt}` — plain text color
- `{res}` — result/highlight color
- `{err}` — error color
- `{bf:text}` — bold
- `{it:text}` — italic
- `{cmd:text}` — command formatting
- `{hline 60}` — horizontal rule
- `{pstd}` — standard paragraph indent
- `{phang}` — hanging indent
- `{phang2}` — double hanging indent
- `{p_end}` — end paragraph
- `{browse "URL"}` — clickable link
- `{manhelp cmd SECTION}` — link to Stata manual

## Build Script Template

```python
#!/usr/bin/env python3
"""Build Stata plugins for multiple platforms."""
import subprocess
import sys

PLATFORMS = {
    'darwin-arm64': {
        'cc': 'gcc',
        'cflags': '-O3 -fPIC -DSYSTEM=APPLEMAC -arch arm64',
        'ldflags': '-bundle -arch arm64',
    },
    'darwin-x86_64': {
        'cc': 'gcc',
        'cflags': '-O3 -fPIC -DSYSTEM=APPLEMAC -target x86_64-apple-macos10.12',
        'ldflags': '-bundle -target x86_64-apple-macos10.12',
    },
    'linux-x86_64': {
        'cc': 'gcc',
        'cflags': '-O3 -fPIC -DSYSTEM=OPUNIX',
        'ldflags': '-shared',
    },
    'windows-x86_64': {
        'cc': 'x86_64-w64-mingw32-gcc',
        'cflags': '-O3 -DSYSTEM=STWIN32',
        'ldflags': '-shared',
    },
}

def build_plugin(name, sources, platforms=None):
    """Build a plugin for specified platforms."""
    if platforms is None:
        platforms = PLATFORMS.keys()

    for platform in platforms:
        cfg = PLATFORMS[platform]
        output = f"{name}.{platform}.plugin"
        cmd = (
            f"{cfg['cc']} {cfg['cflags']} {cfg['ldflags']} "
            f"-o {output} {' '.join(sources)}"
        )
        # Add pthreads
        if 'win' in platform:
            cmd += " -lwinpthread"
        else:
            cmd += " -pthread"

        print(f"Building {output}...")
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"FAILED: {result.stderr}")
            sys.exit(1)
        print(f"  OK")

if __name__ == '__main__':
    build_plugin(
        'myplugin',
        ['algorithm.c', 'stplugin.c'],
    )
```

## Naming Conventions

- Use `method()` not `model()` for method selection options
- Use `generate()` (abbreviation `gen()`) for output variable naming
- Use `replace` as a flag option, not `replace()`
- Plugin files: `algorithm_plugin.platform.plugin`
- .ado files: lowercase, underscores for multi-word commands
- Stata convention: options use lowercase, abbreviations capitalized (`GENerate`, `MAXDepth`)
- Target Stata 14.0+ for plugin support (`version 14.0`)

## Useful Stata Idioms

- `quietly` — suppresses output (use liberally in wrapper code)
- `capture` — suppresses errors and sets `_rc`
- `noisily` inside `capture` — re-enables display while still capturing rc
- `tempvar`, `tempfile` — auto-cleaned temporary names
- `preserve` / `restore` — save/restore dataset state
- `gettoken depvar indepvars : varlist` — split varlist into depvar + rest
