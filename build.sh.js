#!/usr/bin/env bun

import { $ } from "bun"
import info from "./info.json"

const commitShort = (await $`git rev-parse --short HEAD`.text()).trim()
const zipName = `${info.name}_${info.version}`
const folderName = `${zipName}+${commitShort}`
await $`git archive -o ${zipName}.zip --prefix=${folderName}/ HEAD ":(exclude)${import.meta.path}"`
