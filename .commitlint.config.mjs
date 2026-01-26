export default {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'type-enum': [
      2,
      'always',
      [
        'feat',     // New feature
        'fix',      // Bug fix
        'docs',     // Documentation changes
        'content',  // New website content
        'style',    // Content style changes
        'chore',    // Maintenance tasks
        'ci',       // CI/CD changes
        'build',    // Build system changes
      ],
    ],
    'subject-case': [2, 'always', ['lower-case', 'sentence-case']],
    'header-max-length': [2, 'always', 100],
  },
};
