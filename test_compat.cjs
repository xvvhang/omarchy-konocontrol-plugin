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

context.collected = ['omarchy.audio', 'omarchy.elsewhen']
vm.runInContext(`${qmlFunction('isCollected')}\n${qmlFunction('hasOpenCollectedPanel')}`, context)
context.slots = [rc('omarchy.audio'), rc('omarchy.elsewhen'), rc('omarchy.network')]
assert.equal(context.hasOpenCollectedPanel(), false)
context.slots[2].activeItem.opened = true
assert.equal(context.hasOpenCollectedPanel(), false, 'uncollected panels must not highlight Konocontrol')
context.slots[0].activeItem.opened = true
assert.equal(context.hasOpenCollectedPanel(), true, 'collected detail panels keep the bar mark')
context.slots[0].activeItem.opened = false
context.slots[1].activeItem.popupOpen = true
assert.equal(context.hasOpenCollectedPanel(), true, 'popupOpen widgets also keep the bar mark')
context.slots[1].activeItem.popupOpen = false
assert.equal(context.hasOpenCollectedPanel(), false, 'closing the detail panel clears the mark')
context.slots[0].activeItem = null
assert.equal(context.hasOpenCollectedPanel(), false, 'unloaded widgets are safe')
console.log('Collected panel bar highlight checks passed')

assert.match(source, /Binding\s*\{\s*target: host\.slot\s*property: "clip"\s*when: host\.borrowed !== null && host\.slot !== null\s*value: true\s*restoreMode: Binding\.RestoreBindingOrValue\s*\}/,
  'borrowed widgets must clip the empty original bar slot and restore clipping on release')
console.log('Collected slot highlight clipping check passed')

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

const colorContext = {
  nativeItem: {children: [
    {triggerPress() {}, foreground: '#000000', useActiveColor: true, opticalSize: 20},
    {triggerPress() {}, foreground: '#000000', useActiveColor: true},
    {foreground: '#000000'},
  ]},
  sizedIcons: [],
  panelButtons: [],
}
vm.createContext(colorContext)
vm.runInContext(qmlFunction('syncIconSizes'), colorContext)
colorContext.syncIconSizes()
assert.equal(colorContext.panelButtons.length, 2, 'discover both glyph and label buttons for panel colors')
assert.equal(colorContext.sizedIcons.length, 1, 'size overrides remain limited to icon buttons')
const buttons = colorContext.panelButtons
colorContext.syncIconSizes()
assert.equal(colorContext.panelButtons, buttons, 'unchanged scans must preserve color delegates')
colorContext.nativeItem = null
colorContext.syncIconSizes()
assert.equal(colorContext.panelButtons.length, 0, 'unloaded buttons must be released')
assert.match(source, /property: "foreground"\s*when: host\.borrowed !== null\s*value: root\.foreground\s*restoreMode: Binding\.RestoreBindingOrValue/)
assert.match(source, /property: "useActiveColor"\s*when: host\.borrowed !== null\s*value: false\s*restoreMode: Binding\.RestoreBindingOrValue/)
assert.match(indicators, /foreground: Qt\.binding\(function\(\) \{ return root\.foreground \}\)/)
assert.match(indicators, /useActiveColor: false/)
console.log('Panel icon color and binding restoration checks passed')

const scrollContext = {
  contentY: 0,
  maxScroll: 200,
  Style: {space: v => v, duration: v => v},
  scrollAnim: {
    running: false,
    from: 0,
    to: 0,
    duration: 0,
    start() { this.running = true },
    stop() { this.running = false },
  },
}
vm.createContext(scrollContext)
vm.runInContext(qmlFunction('scrollByWheel'), scrollContext)
scrollContext.scrollByWheel(-35, 0, true)
assert.equal(scrollContext.contentY, 35, 'pixelDelta tracks touchpad 1:1')
assert.equal(scrollContext.scrollAnim.running, false)
scrollContext.scrollByWheel(0, -120, false)
assert.equal(scrollContext.scrollAnim.running, true, 'mouse wheel uses smooth animation')
assert.equal(scrollContext.scrollAnim.from, 35)
assert.equal(scrollContext.scrollAnim.to, 95)
scrollContext.scrollByWheel(0, -120, false)
assert.equal(scrollContext.scrollAnim.to, 155, 'rapid mouse wheel ticks accumulate cleanly')
scrollContext.scrollByWheel(0, -240, false)
assert.equal(scrollContext.scrollAnim.to, 200, 'scroll target clamps to maxScroll')
scrollContext.scrollByWheel(40, 0, true)
assert.equal(scrollContext.scrollAnim.running, false, 'touchpad cancels mouse animation')
assert.equal(scrollContext.contentY, 0, 'pixelDelta clamps at top')
scrollContext.Style.duration = () => 0
scrollContext.scrollByWheel(0, -120, false)
assert.equal(scrollContext.contentY, 60, 'reduced motion snaps immediately')
assert.equal(scrollContext.scrollAnim.running, false)
assert.match(source, /id: scrollWheelOverlay[\s\S]*?z: 100[\s\S]*?WheelHandler\s*\{\s*target: null/)
const cardMouseBlock = source.match(/MouseArea\s*\{\s*id: cardMouse[\s\S]*?\n\s{16}\}/)
assert.ok(cardMouseBlock, 'cardMouse block should exist')
assert.doesNotMatch(cardMouseBlock[0], /onWheel:/, 'cardMouse must not swallow wheel events')
assert.doesNotMatch(source, /\(root\.opened \|\| root\.returnOwner === host\.nativeItem\)/,
  'escape-target polling must not spin while only the drawer is open')
console.log('Panel scrolling and timer regression checks passed')
