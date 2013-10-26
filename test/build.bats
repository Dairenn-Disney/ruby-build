#!/usr/bin/env bats

load test_helper
export RUBY_BUILD_CACHE_PATH="$TMP/cache"
export MAKE=make

setup() {
  mkdir -p "$INSTALL_ROOT"
  stub md5 false
  stub curl false
}

cached_tarball() {
  mkdir -p "$RUBY_BUILD_CACHE_PATH"
  pushd "$RUBY_BUILD_CACHE_PATH" >/dev/null
  tarball "$@"
  popd >/dev/null
}

tarball() {
  local name="$1"
  local path="$PWD/$name"
  local configure="$path/configure"
  shift 1

  mkdir -p "$path"
  cat > "$configure" <<OUT
#!$BASH
echo "$name: \$@" >> build.log
OUT
  chmod +x "$configure"

  for file; do
    mkdir -p "$(dirname "${path}/${file}")"
    touch "${path}/${file}"
  done

  tar czf "${path}.tar.gz" -C "${path%/*}" "$name"
}

stub_make_install() {
  stub "$MAKE" \
    " : echo \"$MAKE \$@\" >> build.log" \
    "install : cat build.log >> '$INSTALL_ROOT/build.log'"
}

assert_build_log() {
  run cat "$INSTALL_ROOT/build.log"
  assert_output
}

@test "yaml is installed for ruby" {
  cached_tarball "yaml-0.1.4"
  cached_tarball "ruby-2.0.0"

  stub brew false
  stub_make_install
  stub_make_install

  install_fixture definitions/needs-yaml
  assert_success

  unstub make

  assert_build_log <<OUT
yaml-0.1.4: --prefix=$INSTALL_ROOT
make -j 2
ruby-2.0.0: --prefix=$INSTALL_ROOT
make -j 2
OUT
}

@test "yaml is linked from Homebrew" {
  cached_tarball "ruby-2.0.0"

  brew_libdir="$TMP/homebrew-yaml"
  mkdir -p "$brew_libdir"

  stub brew "--prefix libyaml : echo '$brew_libdir'"
  stub_make_install

  install_fixture definitions/needs-yaml
  assert_success

  unstub brew
  unstub make

  assert_build_log <<OUT
ruby-2.0.0: --prefix=$INSTALL_ROOT --with-libyaml-dir=$brew_libdir
make -j 2
OUT
}

@test "custom relative install destination" {
  export RUBY_BUILD_CACHE_PATH="$FIXTURE_ROOT"

  cd "$TMP"
  install_fixture definitions/without-checksum ./here
  assert_success
  assert [ -x ./here/bin/package ]
}

@test "make on FreeBSD defaults to gmake" {
  cached_tarball "ruby-2.0.0"

  stub uname "-s : echo FreeBSD"
  MAKE=gmake stub_make_install

  MAKE= install_fixture definitions/vanilla-ruby
  assert_success

  unstub gmake
  unstub uname
}

@test "copy strategy forces overwrite" {
  export RUBY_BUILD_CACHE_PATH="$FIXTURE_ROOT"

  mkdir -p "$INSTALL_ROOT/bin"
  touch "$INSTALL_ROOT/bin/package"
  chmod -w "$INSTALL_ROOT/bin/package"

  install_fixture definitions/without-checksum
  assert_success

  run "$INSTALL_ROOT/bin/package" "world"
  assert_success "hello world"
}

@test "mruby strategy overwrites non-writable files" {
  cached_tarball "mruby-1.0" build/host/bin/{mruby,mirb}

  mkdir -p "$INSTALL_ROOT/bin"
  touch "$INSTALL_ROOT/bin/mruby"
  chmod -w "$INSTALL_ROOT/bin/mruby"

  stub gem false
  stub rake '--version : echo 1' true

  run_inline_definition <<DEF
install_package "mruby-1.0" "http://ruby-lang.org/pub/mruby-1.0.tar.gz" mruby
DEF
  assert_success

  unstub rake

  assert [ -w "$INSTALL_ROOT/bin/mruby" ]
  assert [ -e "$INSTALL_ROOT/bin/ruby" ]
  assert [ -e "$INSTALL_ROOT/bin/irb" ]
}

@test "mruby strategy fetches rake if missing" {
  cached_tarball "mruby-1.0" build/host/bin/mruby

  stub rake '--version : false' true
  stub gem 'install rake -v *10.1.0 : true'

  run_inline_definition <<DEF
install_package "mruby-1.0" "http://ruby-lang.org/pub/mruby-1.0.tar.gz" mruby
DEF
  assert_success

  unstub gem
  unstub rake
}

@test "rbx uses bundle then rake" {
  cached_tarball "rubinius-2.0.0" "Gemfile"

  stub gem false
  stub rake false
  stub bundle \
    '--version : echo 1' \
    ' : echo bundle >> build.log' \
    '--version : echo 1' \
    " exec rake install : { cat build.log; echo bundle \"\$@\"; } >> '$INSTALL_ROOT/build.log'"

  run_inline_definition <<DEF
install_package "rubinius-2.0.0" "http://releases.rubini.us/rubinius-2.0.0.tar.gz" rbx
DEF
  assert_success

  unstub bundle

  assert_build_log <<OUT
bundle
rubinius-2.0.0: --prefix=$INSTALL_ROOT
bundle exec rake install
OUT
}