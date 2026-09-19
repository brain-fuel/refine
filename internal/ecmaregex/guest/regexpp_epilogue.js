globalThis.__refineRegexppSyntaxError = exports.RegExpSyntaxError;
globalThis.__refineRegexValidate = pattern => {
    new exports.RegExpValidator({ ecmaVersion: 2020 }).validatePattern(
        pattern, 0, pattern.length, { unicode: true, unicodeSets: false });
};
globalThis.__refineRegexCompile = pattern => new RegExp(pattern, 'u');
globalThis.__refineRegexTest = (compiled, subject) => compiled.test(subject);
