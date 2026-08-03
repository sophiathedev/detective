// LiveSvelte's public barrel also exports its server renderer, which pulls
// node:async_hooks into Vite's browser graph. Keep the client entry isolated.
export {getHooks} from "../../deps/live_svelte/assets/js/live_svelte/hooks.svelte.js"
