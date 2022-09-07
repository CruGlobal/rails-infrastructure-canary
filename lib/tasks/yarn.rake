# Force a `yarn install` before assets:precompile
Rake::Task["assets:precompile"].enhance ["yarn:install"]
