#!/usr/bin/env python3

# -- Imports --
import sys
import os
import logging
import configparser
from pathlib import Path
import argparse
import git as gp
from manic.utils import execute_subprocess, fatal_error
from manic.externals_description import read_externals_description_file
from manic.externals_description import create_externals_description


# -- Constants --
LOG_FILE_NAME='update_ext.log'


def parse_args(args=None):
    '''Setup command-line arguments and parse them'''
    parser = argparse.ArgumentParser()

    parser.add_argument("--externals",
            nargs="*",
            help="Only do this for specified externals")

    opts = parser.parse_args(args)
    return opts


def exe_stat(cmd):
    return execute_subprocess(cmd, status_to_caller=True)


def exe_ret(cmd):
    return execute_subprocess(cmd, status_to_caller=True, output_to_caller=True)


def fetch_source(gcmd, fsrc):
    return gcmd.fetch(fsrc)


def checkout_ref(gcmd, ref):
    return gcmd.checkout(ref)


def git_recent_tag(gcmd):
    return gcmd.describe('--exact-match', '--tags', 'HEAD')


def ew_ext_filter(pair):
    k,ext = pair
    if "EarthWorksOrg" not in ext['repo']['repo_url'] \
            or k == 'ccs_config' or k == 'cam':
        return False
    else:
        return True


def get_ext_dict(root_dir, ext_file, exts=None, excl=None):
    data = read_externals_description_file(root_dir, ext_file)
    data = create_externals_description(data, components=exts, exclude=excl)
    return data


def write_ext_dict(root_dir, ext_file, data):
    parser = configparser.ConfigParser()
    parser.read_dict(data)
    with open(root_dir / ext_file, 'w') as f:
        parser.write(f)


def git_tag_msg(gcmd,tag):
    return gcmd.tag('-l', '-n99', tag)

def msgify(msgs):
    imsg=msgs[0]+'\n\n'
    for m in msgs:
        imsg = imsg+'\n'+m
    return imsg 

def merge_ref(gcmd, ref, msgs):
    return gcmd.merge('--no-ff', ref, '-m', msgify(msgs))


def new_ewm_tag(prev_tag):
    if 'release' in prev_tag:
        ntag = prev_tag.replace('release-ew', '')
        ntag = f"ewm-{ntag}.000"
    else:
        nnum = int(prev_tag.split('.')[-1])+1
        ntag = ntag[:-3]+f'{nnum:03}'
    return ntag


def new_ext_tag(prev_tag):
    if 'release' in prev_tag:
        ntag = prev_tag.replace('release-', '')+'.000'
    else:
        nnum = int(prev_tag.split('.')[-1])+1
        ntag = ntag[:-3]+f'{nnum:03}'

    return ntag


def mergeReleaseToDevelop_ext(comp, ext, m_tag, d_tag, r_ver):
    stats = {}
    print(f"+ {comp} merge {m_tag}")
    # Ensure we're on develop branch
    stats['check'],cmsg = checkout_ref('ew-develop')
    if stats['check'] != 0:
        msg = f"-Failed to checkout out ew-develop branch in {comp}"
        print(msg)
        return None


    # Merge branch
    mmsgs = [f"Merge tag '{m_tag}' into 'ew-develop'",
             f'Post-release to ensure release tag is ancestor of develop work']
    stats['merge'] = merge_ref(m_tag, mmsgs)
    # Create new tag
    new_tag = new_ext_tag(m_tag)
    if not new_tag:
        msg = f"- Failed to create new tag name for {comp}"
        print(msg)
        return None
    last_tagLine = git_tag_msg(d_tag).splitlines()[-1]
    tagmsgs = [f'Incorporate release tag after EWM-v{r_ver} release',
               last_tagLine]

    # Update tag in ext
    cmd = ['git', 'tag', '-a', new_tag]
    for msg in tagmsgs:
        cmd.extend(['-m', msg])
    stats['tag'], oput = exe_ret(cmd)
    if stats['tag'] != 0:
        msg = f"- Failed to create {new_tag} in git"
        print(msg)
        print(f'cmd={cmd}\ncmdOut={oput}\n')
        sys.exit(1)

    # Push tags and branches
    cmd = ['git', 'push', 'origin', 'ew-develop', new_tag]
    execute_subprocess(cmd)
    # if p_stat != 0:
    #     msg = f"- Failed to push ew-develop and {new_tag} to origin"
    #     print(msg)

    success = all(s == 0 for s in stats.values())
    if not success:
        print(f"\tfailed for {comp}")
        stat_str = ','.join([str((k,v)) for k,v in stats.items()])
        print(f"\tstatuses:{stat_str}")
        return None

    print(f"\tsuccess for {comp}")
    return new_tag

def update_externals(root_dir, update_dict):
    parser = configparser.ConfigParser()
    parser.read_dict(update_dict)
    with open(root_dir / "Externals.cfg", 'w') as f:
        parser.write(f)

    # Over done code to remove blank line at end of file
    with open(root_dir / "Externals.cfg", "r+", encoding="utf_8") as f:
        # Start and end of file and seek backwards for a newline char
        # Once found, delete everything that comes after it
        f.seek(0, os.SEEK_END)
        pos = f.tell() -1
        while pos > 0 and f.read(1) != "\n":
            pos -= 1
            f.seek(pos, os.SEEK_SET)
        pos += 1
        if pos > 0:
            f.seek(pos, os.SEEK_SET)
            f.truncate()


def mergeReleaseToDevelop_EWRepo(root_dir, r_ver, r_branch, r_tag, r_tags, d_branch, d_tags, data):
    # Perform release tag merge for the top-level
    mmsgs = [f"Merge tag '{r_tag}' into '{d_branch}'",
             f'Post-release to ensure release tag is ancestor of develop work']
    stat = merge_ref(r_tag, mmsgs)

    # For each EW external, merge its associated release tag
    for k,ext in data.items():
        if k not in r_tags.keys():
            continue
        epath = root_dir / ext['local_path']
        os.chdir(epath)
        nd_tag = mergeReleaseToDevelop_ext(k,ext, r_tags[k], d_tags[k], r_ver)
        if nd_tag:
            data[k]['tag'] = nd_tag
        os.chdir(root_dir)

    print('+ Editing Externals.cfg with new external tags')
    # Update Externals.cfg with new tags and make EW commit+tag
    update_externals(root_dir, data)
    sys.exit(1)
    cmd = ['git', 'add', 'Externals.cfg']
    u_stat = exe_stat(cmd)
    if u_stat != 0:
        msg = f'Failed to add Externals.cfg to commit it. Aborting'
        fatal_error(msg)

    cmsg = f"Roll over external tags for post-v{r_ver} release in develop branch"
    cmd = ['git', 'commit', '-m', cmsg]
    c_stat, oput = exe_ret(cmd)
    if c_stat != 0:
        msg = '- Failed to commit changes for Externals.cfg. Aborting'
        fatal_error(msg)

    d_tag = new_ewm_tag(r_tag)
    tmsg = f"Start of new development after release of EWM-v{r_ver}"
    cmd = ['git', 'tag', '-a', d_tag, '-m', tmsg]
    t_stat, oput = exe_ret(cmd)
    if t_stat != 0:
        msg = f"- Failed to create tag {d_tag}"

    # # Push tag and branch
    # cmd = ['git', 'push', 'origin', 'develop', d_tag]
    # p_stat, oput = exe_ret(cmd)
    # if p_stat != 0:
    #     msg = f"- Failed to push develop and {new-tag} to origin"
    #     print(msg)


if __name__ == "__main__":
    args = parse_args()
    logging.basicConfig(filename=LOG_FILE_NAME,
                        format='%(levelname)s : %(asctime)s : %(message)s',
                        datefmt='%Y-%m-%d %H:%M:%S',
                        level=logging.DEBUG)
    root_dir = Path.cwd()
    ext_file = root_dir / "Externals.cfg"

    fetch_source('origin')
    checkout_ref('main')
    update_data = read_externals_description_file(root_dir, ext_file)
    update_data = {s:dict(update_data.items(s)) for s in update_data.sections()}
    stat, recent_tag = git_recent_tag()

    if 'release' not in recent_tag:
        msg = f'- Error most recent tag {recent_tag} on main is not a release tag\n'+\
              'Ensure there is a release being done'
        print(msg)
        sys.exit(1)
    r_tag = recent_tag
    r_ver = recent_tag.replace('release-ew', '')
    r_branch = 'main'
    r_data = get_ext_dict(root_dir, ext_file)
    r_tags = {k:v['repo']['tag'] for (k,v) in r_data.items() if ew_ext_filter((k,v))}

    d_branch = 'develop'
    checkout_ref(d_branch)
    d_data = get_ext_dict(root_dir, ext_file)
    d_tags = {k:v['repo']['tag'] for (k,v) in d_data.items() if ew_ext_filter((k,v))}

    print(f'Updating develop branch of repos after EWM release {r_ver}')
    repo_str = ', '.join(d_tags.keys())
    print(f'\tRepos {repo_str}')

    mergeReleaseToDevelop_EWRepo(root_dir, r_ver, r_branch, r_tag, r_tags, d_branch, d_tags, update_data)
