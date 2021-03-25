#!/usr/bin/env bash

# Inspired by https://gitlab.com/ralt/linux-packaging/-/blob/eae586eaad5d6448121c53412ff3f2de712b24ca/.ci/build.sh.

set -xe

gem install --no-document fpm &> /dev/null

export PATH=~/.gem/ruby/$(ls ~/.gem/ruby)/bin:$PATH

git clone --depth=1 --branch=sbcl-2.0.10 https://github.com/sbcl/sbcl.git ~/sbcl &> /dev/null
(
    cd ~/sbcl
    set +e
    sh make.sh --fancy --with-sb-linkable-runtime --with-sb-dynamic-core &> sbcl-build.log
    code=$?
    set -e
    test $code = 0 || (cat sbcl-build.log && exit 1)

    sh install.sh &> /dev/null
)

export SBCL_HOME=/usr/local/lib/sbcl

curl -O https://beta.quicklisp.org/quicklisp.lisp && sbcl --load quicklisp.lisp --eval '(quicklisp-quickstart:install)' --eval '(ql:add-to-init-file)' --quit &> /dev/null
rm quicklisp.lisp

mkdir -p ~/common-lisp
git clone --depth=1 https://gitlab.com/ralt/linux-packaging.git ~/common-lisp/linux-packaging/ &> /dev/null
## Modern ASDF needed.
git clone --depth=1 https://gitlab.common-lisp.net/asdf/asdf.git ~/common-lisp/asdf/ &> /dev/null

mkdir -p ~/.config/common-lisp/source-registry.conf.d/
echo "(:tree \"$PWD/\")" >> ~/.config/common-lisp/source-registry.conf.d/linux-packaging.conf

## Prepare desktop file.
sbcl --eval '(require "asdf")' \
		 --load ~/quicklisp/setup.lisp \
		 --eval "(ql:quickload :nyxt)" \
		 --eval '(with-open-file (stream "version" :direction :output :if-exists :supersede) (format stream "~a" nyxt:+version+))' \
		 --quit
sed -i "s/VERSION/$(cat version)/" assets/nyxt.desktop

echo "==> LDCONFIG -p"
ldconfig -p
echo "==> LDCONFIG rm"
rm /etc/ld.so.cache
echo "==> LDCONFIG"
ldconfig
echo "==> LDCONFIG /usr"
ldconfig /usr
echo "==> LDCONFIG -p"
ldconfig -p
echo "==> LDCONFIG DONE"
echo "==> LDD old"
ldd /usr/lib/x86_64-linux-gnu/libwebkit2gtk-4.0.so
echo "==> LN"
ln -sv /usr/lib/x86_64-linux-gnu/libwebkit2gtk-4.0.so /lib/x86_64-linux-gnu/libwebkit2gtk-4.0.so
ln -sv /usr/lib/x86_64-linux-gnu/libwebkit2gtk-4.0.so.37 /lib/x86_64-linux-gnu/libwebkit2gtk-4.0.so.37
echo "==> LDD new"
ldd /lib/x86_64-linux-gnu/libwebkit2gtk-4.0.so
echo "==> LN DONE"

sbcl \
    --eval '(setf *debugger-hook* (lambda (c h) (declare (ignore h)) (format t "~A~%" c) (sb-ext:quit :unix-status -1)))' \
    --load ~/quicklisp/setup.lisp \
    --eval "(ql:quickload :linux-packaging)" \
    --eval "(ql:quickload :nyxt)" \
    --eval "(ql:quickload :nyxt-ubuntu-package)" \
		--eval '(format t "==> CFFI foreign libraries:~%")' \
		--eval '(let ((*print-right-margin* 9999)) (describe (find (quote cl-webkit2::libwebkit2) (cffi:list-foreign-libraries) :key (quote cffi:foreign-library-name))))' \
		--eval "(asdf:make :nyxt-ubuntu-package)" \
    --quit
