## Development

The release requires the Ruby gem Bundler (used by the vendoring script):

```
gem install bundler
```

With bundler installed, run the vendoring script:

```
./scripts/vendor_gems
```

Then create the BOSH release:

```
bosh create release --force --with-tarball
```

The release is now ready for use. If everything works, commit the changes including the updated gems.

At the end of the CLI output there will be "Release tarball" path. You can use generated tarball with experimental `bosh-micro` CLI.
