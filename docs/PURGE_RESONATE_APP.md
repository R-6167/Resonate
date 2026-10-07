# Purge remaining Resonate app files from Wire_dsp_engine

This branch now has the **DSP ENGINE** package at the root (`include/`, `src/`, `CMakeLists.txt`).

GitHub’s API cannot cheaply delete thousands of Flutter/Android app files in one shot.
To make the branch **only** DSP ENGINE (orphan rewrite), run **locally**:

```bash
git fetch origin
git checkout Wire_dsp_engine
git pull origin Wire_dsp_engine

# New history containing only engine files
git checkout --orphan dsp-engine-only

# Keep only the engine package
git rm -rf --cached .
git add include src tools CMakeLists.txt README.md LICENSE .gitignore \
        docs/ARCHITECTURE.md docs/PURGE_RESONATE_APP.md \
        .github/workflows/dsp-engine-ci.yml
# optional: docs you want to keep
git add docs/ || true

git commit -m "DSP ENGINE only — remove Resonate app from Wire_dsp_engine"

git branch -M Wire_dsp_engine
git push --force origin Wire_dsp_engine
```

**Warning:** `--force` rewrites this branch only. Other branches (`main`, `dj_Mode`, …) keep the full Resonate app.

After that, the branch tree should look like:

```
include/dsp_engine.h
src/dsp_engine_core.cpp
src/dsp_stress.cpp
tools/stress_main.cpp
CMakeLists.txt
README.md
LICENSE
.gitignore
docs/
.github/workflows/dsp-engine-ci.yml
```
