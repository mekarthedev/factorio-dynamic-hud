#!/usr/bin/env bun

import { $ } from "bun"
import info from "./info.json"

const zipName = `${info.name}_${info.version}`
await $`git archive -o ${zipName}.zip --prefix=${zipName}/ HEAD ":(exclude)${import.meta.path}"`
