# Managed Library test-fixture cleanup

Older collection tests used Kromora's production managed Library by default. If those tests have
already been run on a development Mac, inspect the directory below before removing anything:

```sh
library="$HOME/Library/Application Support/Kromora/Library"
ls -lh "$library"
file "$library"/* | sort
```

The known orphaned fixtures have these characteristics:

- basename: `<16-hex-token>-<Picked|Filtered|Reserved|Overflow|Digest|Portrait|First>.jpeg`
  or `<16-hex-token>-IMG_0042.HEIC`
- size: 793 bytes for the 32×24 JPEGs, or 869 bytes for the 80×60 JPEGs
- `file(1)` dimensions: 32×24 JPEG (or 80×60 JPEG)
- pixels: the generated solid brown fixture colour (`red: 0.5`, `green: 0.4`, `blue: 0.3`)

On macOS, confirm dimensions for each candidate before considering removal:

```sh
for path in "$library"/*; do
    name="$(basename "$path")"
    if [[ "$name" =~ '^[0-9a-f]{16}-(Picked|Filtered|Reserved|Overflow|Digest|Portrait|First)\.jpeg$' \
       || "$name" =~ '^[0-9a-f]{16}-IMG_0042\.HEIC$' ]]; then
        file "$path"
        sips -g pixelWidth -g pixelHeight "$path"
    fi
done
```

This is an inspection-only procedure. Do not run a deletion command automatically. After confirming
that every listed candidate has the expected name, size, dimensions, and brown pixels, remove only
the individually confirmed paths and leave all other managed-library files untouched.
