"""Exercise the budget gate with KOReader's LuaJIT, never system Lua/SQLite.

Usage: python3 tools/check_budget_failures.py <koreader directory> <plugin> <mobile.db>
Uses disposable profiles/baselines; neither the real baseline nor DB is changed.
"""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def main():
    if len(sys.argv) != 4:
        raise SystemExit(__doc__)
    runtime, plugin, database = (Path(value).resolve() for value in sys.argv[1:])
    native_luajit = runtime / "luajit"
    assert native_luajit.is_file() and (runtime / "setupkoenv.lua").is_file(), "KOReader runtime required"
    baseline = json.loads((plugin / "tools/budget_baseline.json").read_text())
    with tempfile.TemporaryDirectory(prefix="dpd-budget-gate-") as folder:
        run = Path(folder)
        env = os.environ.copy()
        env.update(KO_HOME=str(run / "profile"), KO_MULTIUSER="1",
                   XDG_CONFIG_HOME=str(run / "profile"), SDL_VIDEODRIVER="dummy")
        (run / "profile").mkdir()

        def check(name, data, success, message=None, shim=None, update=False):
            target = run / (name + ".json")
            target.write_text(json.dumps(data))
            before = target.read_bytes()
            args = [str(native_luajit), str(shim or plugin / "tools/check_budget.lua"),
                    str(plugin), str(database), "--baseline", str(target)]
            if update:
                args.append("--update-baseline")
            result = subprocess.run(args, cwd=runtime, env=env, text=True,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60)
            assert (result.returncode == 0) == success, (name, result.stdout[-2000:])
            if message:
                assert message in result.stdout, (name, result.stdout[-2000:])
            if not success:
                assert target.read_bytes() == before, "failure rewrote baseline: " + name
            print("PASS: " + name, flush=True)
            return json.loads(target.read_text())

        check("equal", baseline, True)
        # Measure into a disposable file after checking the committed ceilings.
        # Smaller HTML must still exercise rejection: a ceiling minus one may
        # remain above the actual output after a reviewed rendering change.
        observed = check("measure-current", baseline, True, update=True)
        raised = copy.deepcopy(baseline)
        metrics = ["queries", "rows", "payload_bytes", "html_bytes"]
        for metric in metrics:
            raised["cases"][0]["fresh"][metric] += 1
        check("below-ceilings", raised, True)
        for metric in metrics:
            lower = copy.deepcopy(baseline)
            lower["cases"][0]["fresh"][metric] = observed["cases"][0]["fresh"][metric] - 1
            check("exceeded-" + metric, lower, False, metric + " ")
        for metric in metrics[:3]:
            lower = copy.deepcopy(baseline)
            lower["opening"][metric] = observed["opening"][metric] - 1
            check("opening-" + metric, lower, False, "DB open: " + metric)
        for name, section, field, value in [("different-db", "database", "schema", "999"),
                                           ("different-settings", "settings", "niggahita", "ṁ")]:
            altered = copy.deepcopy(baseline)
            altered[section][field] = value
            check(name, altered, False, "baseline is for a different DB/settings")

        bootstrap = 'require("setupkoenv"); package.path=arg[1].."/?.lua;"..package.path\n'
        execute = 'assert(loadfile(arg[1].."/tools/check_budget.lua"))()\n'
        # Exercise valid arrowless rows without changing the official DB or
        # committed case list. A respelling with only a "same as" note still
        # needs a disclosure. These runs record only disposable baselines.
        for name, kind, mutation, message in [
            ("analysis-no-new", "no-new", "", None),
            ("analysis-malformed", "malformed", "", None),
            ("analysis-same-note", "same-note", "", None),
            ("analysis-missing-component", "no-new",
             "html=html:gsub('dpd:component/1/2', 'dpd:missing-component/1/2')",
             "missing compound component link"),
            ("analysis-missing-raw", "malformed",
             "html=html:gsub('A &amp; B &lt;&lt; %+%+ C', '')", "missing raw compound analysis"),
            ("analysis-missing-disclosure", "same-note",
             "html=html:gsub('dpd:analysis/1', 'dpd:missing-analysis/1')",
             "missing compound analysis disclosure"),
            ("analysis-unexpected-disclosure", "no-new",
             "html=html .. '<a href=\"dpd:analysis/1\">▸</a>'",
             "unexpected compound analysis disclosure"),
        ]:
            shim = run / (name + ".lua")
            shim.write_text(bootstrap + '''
local Lookup=require("dpd/lookup")
local Deconstruct=require("dpd/deconstruct")
local Render=require("ui/dpd_render")
local get, render=Lookup.get, Render.render
local kind=''' + json.dumps(kind) + '''
Lookup.get=function(self,word,options)
    local value=get(self,word,options)
    if value.query=="bhikkhaveti" then
        local part=value.senses[1].lemma_1:gsub(" [%d.]+$", "")
        if kind=="same-note" then part="budget-respelling" end
        value.components[part]={senses=value.senses, reference_targets={}, total=#value.senses}
        local raw=kind=="malformed" and "A & B << ++ C" or (part .. " + " .. part)
        value.deconstructions=Deconstruct.analyses({raw})
        Lookup.markAnalyses(value)
        assert(not value.deconstructions[1].has_new)
        assert((value.deconstructions[1].same~=nil)==(kind=="same-note"))
    end
    return value
end
Render.render=function(value,...)
    local html=render(value,...)
    if value.query=="bhikkhaveti" then
        ''' + mutation + '''
    end
    return html
end
''' + execute)
            check(name, baseline, message is None, message, shim, update=True)

        for name, sql in {
            "frequency": "SELECT freq_data FROM dpd_headwords LIMIT 1",
            "sutta": "SELECT * FROM sutta_info LIMIT 1",
            "root-detail": "SELECT root_in_comps FROM dpd_roots LIMIT 1",
            "dictionary": "SELECT definition_html FROM dict_entries LIMIT 1",
        }.items():
            shim = run / (name + ".lua")
            shim.write_text(bootstrap + 'local Popup=require("dpd/popup"); local render=Popup.render\n'
                            + 'Popup.render=function(lookup,frame,options) pcall(lookup.db.query,lookup.db,'
                            + json.dumps(sql) + '); return render(lookup,frame,options) end\n' + execute)
            check("lazy-" + name, baseline, False, "unopened", shim, update=True)
        for name, mutation, message in [
            ("missing-sense", "table.remove(value.senses)", "unexpected senses"),
            ("changed-meaning", 'value.senses[1].meaning_combo=""', "result differs from baseline"),
        ]:
            shim = run / (name + ".lua")
            shim.write_text(bootstrap + 'local Lookup=require("dpd/lookup"); local get=Lookup.get\n'
                            + 'Lookup.get=function(self,word,options) local value=get(self,word,options); '
                            + 'if word=="pacchima" then ' + mutation + ' end; return value end\n' + execute)
            check(name, baseline, False, message, shim, update=name == "missing-sense")


if __name__ == "__main__":
    main()
