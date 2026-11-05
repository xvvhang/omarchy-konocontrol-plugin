const assert = require('node:assert/strict')
const fs = require('node:fs')
const vm = require('node:vm')

const source = fs.readFileSync(`${__dirname}/Widget.qml`, 'utf8')
function qmlFunction(name, text = source) {
  const start = text.indexOf(`  function ${name}(`)
  assert.notEqual(start, -1)
  const body = text.indexOf('{', start)
  let depth = 1, end = body + 1
  for (; depth; end++) {
    if (text[end] === '{') depth++
    if (text[end] === '}') depth--
  }
  return text.slice(start, end)
}

const context = {
  slots: [],
  hosts: {count: 0},
  root: {QsWindow: {window: {contentItem: {children: []}}}},
}
context.root.widgetHost = slot => context.widgetHost(slot)
vm.createContext(context)
vm.runInContext(`${qmlFunction('widgetHost')}\n${qmlFunction('discover')}\n${qmlFunction('label')}`, context)

function legacy(id, firstParty = true) {
  return {moduleName: id, firstParty, activeItem: {}, entry: {}, region: 'right'}
}
function rc(id, firstParty = true) {
  const slot = legacy(id)
  delete slot.firstParty
  slot.host = {firstParty, moduleSettings: {}}
  return slot
}

for (const make of [legacy, rc]) {
  const audio = make('omarchy.audio')
  const thirdParty = make('omarchy.impostor', false)
  const tray = make('omarchy.tray')
  const spacer = make('omarchy.spacer')
  const pending = make('omarchy.bluetooth')
  pending.activeItem = null
  context.root.QsWindow.window.contentItem.children = [
    {children: [audio, thirdParty, tray, spacer, pending]},
  ]
  context.discover()
  assert.equal(context.slots.length, 1)
  assert.equal(context.slots[0], audio)
  const previous = context.slots
  context.discover()
  assert.equal(context.slots, previous, 'unchanged scans must not recreate delegates')
}
assert.equal(context.widgetHost(null), null)
assert.equal(context.widgetHost({host: null}), null)
assert.equal(context.widgetHost(rc('omarchy.audio')).firstParty, true)
assert.equal(context.widgetHost(legacy('omarchy.audio')).firstParty, true)
console.log('Legacy and RC widget discovery checks passed')

const worldClock = rc('omarchy.elsewhen')
context.root.QsWindow.window.contentItem.children = [worldClock]
context.discover()
assert.equal(context.slots.length, 1)
assert.equal(context.slots[0], worldClock)
assert.equal(context.label(worldClock.moduleName), 'World Clock')
context.root.QsWindow.window.contentItem.children = []
context.discover()
assert.equal(context.slots.length, 0, 'shells without Elsewhen must not invent a widget')
console.log('World Clock discovery and label checks passed')

const indicators = fs.readFileSync(`${__dirname}/IndicatorStrip.qml`, 'utf8')
let nativeRefreshes = 0, localRefreshes = 0
const refreshContext = {
  root: {nativeIndicators: {refresh() { nativeRefreshes++ }}},
  refreshRequested() { localRefreshes++ },
  indicatorHost: {refreshRequested() { localRefreshes++ }},
}
vm.createContext(refreshContext)
vm.runInContext(`${qmlFunction('refresh', indicators)}\n${qmlFunction('onRefreshRequested', indicators)}`, refreshContext)
refreshContext.refresh()
assert.equal(nativeRefreshes, 1, 'actions must refresh the original bar indicators too')
refreshContext.onRefreshRequested()
assert.equal(nativeRefreshes, 1, 'native notifications must not cause a refresh loop')
assert.equal(localRefreshes, 1)
refreshContext.root.nativeIndicators = null
refreshContext.refresh()
assert.equal(localRefreshes, 2)
console.log('Indicator refresh forwarding checks passed')
