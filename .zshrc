
# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/Users/quangthanhdong/miniforge3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/Users/quangthanhdong/miniforge3/etc/profile.d/conda.sh" ]; then
        . "/Users/quangthanhdong/miniforge3/etc/profile.d/conda.sh"
    else
        export PATH="/Users/quangthanhdong/miniforge3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

# Pyspark
export SPARK_HOME=/usr/local/Cellar/apache-spark/<version>/libexec
export PYSPARK_PYTHON=python3
export PYSPARK_DRIVER_PYTHON=python3
