FROM gcr.io/oss-fuzz-base/base-builder-rust@sha256:433319ea1a6bbea6c1db1915a5d385021908cc62026d9f0efda2270ef6060de3

RUN rustup toolchain install nightly-2026-08-13 --profile minimal --component rust-src

ENV RUSTUP_TOOLCHAIN=nightly-2026-08-13

COPY . $SRC/dev-nav
COPY .clusterfuzzlite/build.sh $SRC/build.sh
WORKDIR $SRC/dev-nav
