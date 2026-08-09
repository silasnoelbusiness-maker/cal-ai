// Empty stub — see vitest.config.ts alias. The real "server-only" package
// throws unconditionally when imported outside Next's "react-server"
// bundling condition, which includes plain Vitest runs. Production code is
// unaffected: this alias only applies inside the test environment.
export {};
