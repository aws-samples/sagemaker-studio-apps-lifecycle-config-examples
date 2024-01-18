from __future__ import absolute_import

from glob import glob
import os
from os.path import basename
from os.path import splitext

from setuptools import find_packages, setup
from distutils.util import convert_path

main_ns = {}
ver_path = convert_path('src/sagemaker_studio_jlab_auto_stop_idle/version.py')
with open(ver_path) as ver_file:
    exec(ver_file.read(), main_ns)

setup(
    name='sagemaker_studio_jlab_auto_stop_idle',
    version=main_ns['__version__'],
    description='Auto-stops idle SageMaker Studio JupyterLab applications.',

    packages=find_packages(where='src', exclude=('test',)),
    package_dir={'': 'src'},
    py_modules=[splitext(basename(path))[0] for path in glob('src/*.py')],

    author='Amazon Web Services',
    url='https://github.com/aws-samples/sagemaker-studio-jupyterlab-lifecycle-config-examples/tree/main/scripts/auto-stop-idle',
    license='MIT-0',

    classifiers=[
        "Development Status :: 5 - Production/Stable",
        "Intended Audience :: Developers",
        "Natural Language :: English",
        "License :: OSI Approved :: MIT-0",
        "Programming Language :: Python",
        'Programming Language :: Python :: 3.9',
        'Programming Language :: Python :: 3.10'
    ],

    install_requires=[],
    extras_require={
    },
)