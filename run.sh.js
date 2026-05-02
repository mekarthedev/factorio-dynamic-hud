import { $ } from "bun"
import os from "node:os"

const instanceName = Bun.argv[Bun.argv.length - 1]
if (!instanceName) { throw "Missing instance name" }

const home = os.homedir()
const executable = `${home}/Downloads/Factorio_2.0.76/bin/x64/factorio.exe`
const originalWriteDir = `${home}/AppData/Roaming/Factorio`
const writeDir = `${process.cwd()}/.factorio-instances/${instanceName}`
const configFile = `${writeDir}/config/config.ini`

await $`mkdir -p ${writeDir}`
await $`cp ${originalWriteDir}/config/config.ini ${configFile}`
await Bun.write(configFile, (await Bun.file(configFile).text()).replace(/^write-data=.*$/m, `write-data=${writeDir}`))

await $`${executable} --fullscreen=false --config=${configFile} --mod-directory=${originalWriteDir}/mods`
