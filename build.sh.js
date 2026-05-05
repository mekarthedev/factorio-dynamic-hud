#!/usr/bin/env bun

import { $ } from "bun"
import info from "./info.json"

const modifiedFiles = (await $`git status --porcelain --untracked-files=no`.text()).trim()
if (modifiedFiles && !Bun.argv.includes("--unsafe")) {
  throw new Error("Uncommitted changes found; stash or discard before archiving.")
}

const infoLua = (await Bun.file("info.lua").text()).match(/\bname\s*=\s*"(?<name>[^"]+)"/)?.groups
if (!infoLua || infoLua.name !== info.name) {
  throw new Error(`info.lua contradicts info.json; found: ${infoLua?.name}, expected: ${info.name}`)
}

const commitShort = (await $`git rev-parse --short HEAD`.text()).trim()
const zipName = `${info.name}_${info.version}`
const folderName = `${zipName}+${commitShort}`
const ignoreFiles = [
  import.meta.path,
  "run.sh.js",
  "README.md",
  ".gitignore",
  ".vscode",
].map(f => ":(exclude)" + f)

await $`git archive -o .ignore/${zipName}.zip --prefix=${folderName}/ HEAD ${ignoreFiles}`
