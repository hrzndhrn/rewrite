# Changelog

## 0.4.1 - 2023/02/04

+ Support the `FreedomFormatter`.
+ Update `Source.save/1` to add a neline at the of file. Previously a newline
  was added at `Source.update/3`.

## 0.4.0 - 2023/02/02

+ Update `Rewrite.TextDiff.format/3` to include more formatting customization.

## 0.3.0 - 2022/12/10

+ Accept glob as `%GlobEx{}` as argument for `Rewrite.Project.read!/1`

## 0.2.0 - 2022/09/08

+ Remove `Rewrite.Issue`. The type of the field `issues` for `Rewrite.Source`
  becomes `[term()]`.
+ Remove `Rewrite.Source.debug_info/2` and `BeamFile` dependency.
+ Add `Rewrite.Project.sources_by_module/2`, `Rewrite.Project.source_by_module/2`
  and `RewriteProject.source_by_module!/2`.
+ Remove `Rewrite.Source.zipper/1`
+ Update `Rewrite.Source.update`. An update can now be made with `:path`, `:ast`,
  and `:code`. An update with a `Sourceror.Zipper.zipper()` is no longer
  supported.
+ Add `Rewrite.Source.from_ast/3`.
+ Add `Rewrite.Source.owner/1`.

## 0.1.1 - 2022/09/07

+ Update `Issue.new/4`.

## 0.1.0 - 2022/09/05

+ The very first version.

+ This package was previously part of Recode. The extracted modules were also
  refactored when they were moved to their own package.
