# Changelog

## 0.2.0 - dev

+ Remove `Rewrite.Issue`. The type of the field `issues` for `Rewrite.Source`
  becomes `[term()]`.
+ Remove `Rewrite.Source.debug_info/2` and `BeamFile` dependency.
+ Add `Rewrite.Project.sources_by_module/2`, `Rewrite.Project.source_by_module/2`
  and `RewriteProject.source_by_module!/2`.

## 0.1.1 - 2022/09/07

+ Update `Issue.new/4`.

## 0.1.0 - 2022/09/05

+ The very first version.

+ This package was previously part of Recode. The extracted modules were also
  refactored when they were moved to their own package.
