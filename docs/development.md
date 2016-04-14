## Development

The release requires the Ruby gem Bundler (used by the vendoring script):

```
gem install bundler
```

With bundler installed, switch to ./src/bosh_azure_cpi and run the vendoring script:

```
./vendor_gems
```

If you are using Ubuntu 14.04, you should replace the bundle in ./vendor_gems with /usr/local/bin/bundle.

Then create the BOSH release:

```
bosh create release --force --with-tarball --name bosh-azure-cpi
```

The release is now ready for use. If everything works, commit the changes including the updated gems.

At the end of the CLI output there will be "Release tarball" path.
