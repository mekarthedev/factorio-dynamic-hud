#!/usr/bin/env bun

import { $ } from "bun"
import info from "./info.json"

const modifiedFiles = (await $`git status --porcelain --untracked-files=no`.text()).trim()
if (modifiedFiles) {
  throw new Error("Uncommitted changes found; stash or discard before archiving.")
}

const commitShort = (await $`git rev-parse --short HEAD`.text()).trim()
const zipName = `${info.name}_${info.version}`
const folderName = `${zipName}+${commitShort}`
const ignoreFiles = [
  import.meta.path,
  ".gitignore",
  "run.sh.js",
].map(f => ":(exclude)" + f)

await $`git archive -o ${zipName}.zip --prefix=${folderName}/ HEAD ${ignoreFiles}`
