#!/usr/bin/env python3
'''
Given a CESM tag, update EarthWorks externals and Externals.cfg
to incorporate those changes
'''

# -- Imports --
import sys
import os
import logging
from pathlib import Path
import argparse
import textwrap
sys.path.append('../../manage_externals')
from manic.utils import execute_subprocess, fatal_error
from manic.externals_description import read_externals_description_file
from manic.externals_description import create_externals_description
# -- Constants --
LOG_FILE_NAME='update_ext.log'

from pprint import PrettyPrinter


def parse_args(args=None):
    '''Setup command-line arguments and parse them'''
    parser = argparse.ArgumentParser()

    parser.add_argument("--cesm-url", "-cu",
            nargs="?",
            default="https://github.com/ESCOMP/CESM",
            help="URL to use for the ESCOMP/CESM repo")
    parser.add_argument("--cesm-tag", "-ct",
            nargs="?",
            required=True,
            help="Tag from ESCOMP/CESM to use to update EarthWorks externals")
    dpath = Path.cwd().parents[2]
    parser.add_argument("--root-dir", "-rd",
            nargs=1,
            default=dpath,
            help=f"Location of EarthWorks Model. Default is {dpath}")
    parser.add_argument("--externals",
            nargs="*",
            help="Only do this for specified externals")

    opts = parser.parse_args(args)
    return opts


def exe_stat(cmd):
    '''Use manic.execute subprocess and return the status'''
    return execute_subprocess(cmd, status_to_caller=True)

def exe_ret(cmd):
    '''Use manic.execute subprocess and return the status and output'''
    return execute_subprocess(cmd, status_to_caller=True, output_to_caller=True)

def get_cesm_extcfg(tag,fpath):
    '''Copy the Externals.cfg file from internet for the given CESM tag'''
    if fpath.exists():
        return
    url = f"https://raw.githubusercontent.com/ESCOMP/CESM/{tag}/Externals.cfg"
    cmd = ['curl', url, '-o', str(fpath)]
    stat = exe_stat(cmd)
    if stat != 0:
        msg = f"- Failed to get Externals.cfg file from {url}"
        print(msg)
        fatal_error(msg)

    return stat

def get_update_dict(rootdir, ew_file, cesm_file, cesmtag, exts=None):
    '''Parse each Externals.cfg file and return a dictionary with needed info and a ConfigParser object of the EarthWorks Externals.cfg'''
    stat = get_cesm_extcfg(cesmtag ,cesm_file)
    if stat != 0:
        return None, None

    ew_data = read_externals_description_file(rootdir, ew_file)
    cesm_data = read_externals_description_file(rootdir, cesm_file)
    ew_extdesc = create_externals_description(ew_data,
                    components=exts, exclude=None)
    cesm_extdesc = create_externals_description(cesm_data,
                     components=exts, exclude=None)
    ret = {}
    for k in ew_extdesc.keys():
        e_repo = ew_extdesc[k]['repo']
        if ('EarthWorksOrg' in e_repo['repo_url']
          and k in cesm_extdesc.keys()):
            e_url = e_repo['repo_url']
            e_name = e_url.replace('https://github.com/','').replace('.git','')
            c_repo = cesm_extdesc[k]['repo']
            c_url = c_repo['repo_url']
            c_name = c_url.replace('https://github.com/','').replace('.git','')
            ret[k] = {
              'local_path':ew_extdesc[k]['local_path'],
              'repo':{
                     'branch':'ew-develop',
                     'repo_url':e_url,
                     'name':e_name,
                     'tag':e_repo['tag']},
              'upstream':{
                     'repo_url':c_url,
                     'name':c_name,
                     'tag':c_repo['tag']}
              }

        elif k in cesm_extdesc.keys():
            # Shared external no EarthWorks modifications, only save the CESM info
            c_repo = cesm_extdesc[k]['repo']
            c_url = c_repo['repo_url']
            c_name = c_url.replace('https://github.com/','').replace('.git','')
            ret[k] = {
              'local_path':ew_extdesc[k]['local_path'],
              'upstream':{
                     'repo_url':c_url,
                     'name':c_name,
                     'tag':c_repo['tag']}
              }

    return ret, ew_data


def setup_ewmodel(rootdir, update, ewbranch, ctag):
    '''Ensure that we are using the correct remote, tag, etc for EarthWorksModel'''
    os.chdir(rootdir)
    uname = 'ew-org'
    url = "https://github.com/EarthWorksOrg/EarthWorks"

    update['ew-model'] = {
            'local_path':str(rootdir),
            'repo':{
                'branch':ewbranch,
                'repo_url':url,
                'name':uname}
            }

    cmd = ["git", "remote", "add", "ew-org", "https://github.com/EarthWorksOrg/EarthWorks"]
    #cmd = ['git', 'remote', 'add', uname, url]
    stat,oput = exe_ret(cmd)
    update['ew-model']['fetch'] = {'remote':stat}
    if stat != 0:
        msg = f"- Failed to add remote {uname} {url} to EarthWorksOrg in {str(rootdir)}"
        print(msg)
        print(f'cmd={cmd}\ncmdOut={oput}\n')
        return False


    # Fetch the tag/branch from this remote
    cmd = ['git', 'fetch', uname, ewbranch]
    stat,oput = exe_ret(cmd)
    update['ew-model']['fetch']['branch'] = stat
    if stat != 0:
        msg = f"- Failed to fetch {ewbranch} from {uname} for EarthWorksOrg in {str(rootdir)}"
        print(msg)
        print(f'cmd={cmd}\ncmdOut={oput}\n')
        return False

    # Create a new branch for this change
    m_branch = f'update/{ctag}'
    cmd = ['git', 'checkout', '-b', m_branch, 'ew-org/develop']
    stat, oput = exe_ret(cmd)
    if stat != 0:
        msg = f'- Failed to create branch {m_branch} in EW repo'
        print(msg)
        print(f'cmd={cmd}\ncmdOut={oput}\n')
        return False
    update['ew-model']['merge']= {'branch':m_branch}
    return True


def setup_remotes(rootdir, update):
    '''Add remotes, fetch develop branch, and mentioned tags'''
    for k,ext in update.items():
        if ext.get('repo') is None or k == 'ew-model':
            # only need to copy CESM tag later, skip this external
            continue
        epath = rootdir / ext['local_path']
        os.chdir(epath)

        # Add the remote
        uname = ext['upstream']['name']
        url = ext['upstream']['repo_url']
        cmd = ['git', 'remote', 'add', uname, url]
        stat,oput = exe_ret(cmd)
        ext['fetch'] = {'remote':stat}
        if stat != 0:
            msg = f"- Failed to add remote {uname} {url} to external {k} in {str(epath)}"
            print(msg)
            print(f'cmd={cmd}\ncmdOut={oput}\n')

        # Fetch the tag from upstream and develop from origin
        utag = ext['upstream']['tag']
        cmd = ['git', 'fetch', uname, 'tag', utag, '--no-tags']
        stat,oput = exe_ret(cmd)
        ext['fetch']['tag'] = stat
        if stat != 0:
            msg = f"- Failed to fetch '{uname}/{utag}'"
            print(msg)
            print(f'cmd={cmd}\ncmdOut={oput}\n')
        cmd = ['git', 'fetch', 'origin', 'ew-develop']
        stat,oput = exe_ret(cmd)
        ext['fetch']['branch'] = stat
        if stat != 0:
            msg = "- Failed to fetch 'origin/ew-develop'"
            print(msg)
            print(f'cmd={cmd}\ncmdOut={oput}\n')

        os.chdir(rootdir)


def merge_branches(rootdir, update, cesmtag):
    '''Perform the merge from CESM version into EW external'''
    stat = -1
    for k, ext in update.items():
        if k == 'ew-model':
            continue
        if ext.get('repo') is None:
            continue
        if ext['fetch'].get('tag') != 0 or ext['fetch'].get('branch') != 0:
            continue

        epath = rootdir / ext['local_path']
        os.chdir(epath)

        # Create branch for the merge
        m_branch = f"update/{cesmtag}/{k}"
        cmd = ['git', 'checkout', '-b', m_branch, 'origin/ew-develop']
        stat,oput = exe_ret(cmd)
        ext['merge'] = {'branch':m_branch}
        if stat != 0:
            msg = '- Failed to create new branch for merge'
            print(msg)
            print(f'cmd={cmd}\ncmdOut={oput}\n')
            os.chdir(rootdir)

        # Perform the merge
        uname = ext['upstream']['name']
        utag = ext['upstream']['tag']
        name = ext['repo']['name']
        branch = ext['repo']['branch']
        s_msg = f"Merge tag '{utag}' from {uname} into '{branch}'"
        b_msg = f"Update {name} with upstream work from 'ESCOMP/CESM/{cesmtag}' version."
        cmd = ['git', 'merge', '--no-ff', utag, '-m', s_msg, '-m', b_msg]
        stat,oput = exe_ret(cmd)
        ext['merge']['stat'] = stat
        if stat != 0:
            msg = '- Merge failed'
            print(msg)
            print(f'cmd={cmd}\ncmdOut={oput}\n')

        os.chdir(rootdir)


def git_wrap(summ, body, col=79):
    '''Insert newline every col characters to wrap a body message
    '''
    wrapbod = '\n'.join(textwrap.wrap(body,width=col,break_long_words=False))
    return summ+"\n\n"+wrapbod


def tag_branches(rootdir, update, cesmtag):
    '''Create an annotated tag for each external updated'''
    for k, ext in update.items():
        if ext.get('repo') is None:
            continue
        if ext['merge'].get('stat') == 0:
            os.chdir(rootdir / ext['local_path'])

            newtag = getnewtag(ext['repo'].get('tag'))
            ustream = ext['upstream']['name']
            utag = ext['upstream']['tag']
            tagmsg = f"Last changes from upstream '{ustream}' tag:'{utag}'"

            cmd = ['git', 'tag', '-a', newtag, '-m', f"Update with version from CESM tag '{cesmtag}'", '-m', tagmsg]
            stat, oput = exe_ret(cmd)
            ext['merge']['tag_stat'] = stat
            if stat != 0:
                msg = '- Tagging failed'
                print(msg)
                print(f'cmd={cmd}\ncmdOut={oput}\n')
            else:
                ext['merge']['tag'] = newtag

            os.chdir(rootdir)


def getnewtag(otag=None):
    '''Use git describe to get most recent tag accessible on branch and increment last number'''
    if otag is None:
        cmd = ['git', 'describe', '--tags', '--abbrev=0']
        stat, oput = exe_ret(cmd)
        if stat != 0:
            msg = "- Failed to fetch most recent tag"
            print(msg)
            print(f'cmd={cmd}\ncmdOut={oput}\n')
            return ''
        otag = oput
    # Increment the last number in the tag and keep 0 padding
    ntag = otag.split('.')
    ntag[-1] = f'{int(ntag[-1])+1:03}'
    ntag = '.'.join(ntag)
    return ntag


def update_file_externals(rootdir, update, cfg_ext, ctag):
    '''Update EarthWorks Externals.cfg file with new tags or those from CESM Externals.cfg'''
    os.chdir(rootdir)
    for k, ext in update.items():
        if k == 'ew-model':
            continue
        if ext.get('merge') is not None:
            # It's a shared external with EarthWorks specific chages
            ntag = ext['merge'].get('tag')
            if ntag is None:
                print(f'- External {k} no tag to update')
                ntag = 'SKIPPED'
        else:
            # It's an external that we can copy from CESM
            ntag = ext['upstream']['tag']
        cfg_ext.set(k, 'tag', ntag)
    with open(rootdir / 'Externals.cfg', 'w', encoding='UTF-8') as f:
        cfg_ext.write(f)

    # Update git
    cmd = ['git', 'add', 'Externals.cfg']
    stat, oput = exe_ret(cmd)
    if stat != 0:
        msg = '- Failed to add Externals.cfg in EW repo'
        print(msg)
        print(f'cmd={cmd}\ncmdOut={oput}\n')
        return
    cmd = ['git', 'commit', '-m', f"Update externals based on CESM tag '{ctag}'"]
    stat, oput = exe_ret(cmd)
    update['ew-model']['merge']['stat'] = stat
    if stat != 0:
        msg = '- Failed to commit changes to Externals.cfg in EW repo'
        print(msg)
        print(f'cmd={cmd}\ncmdOut={oput}\n')
    m_tag = getnewtag()
    t_msgs = [f'Update Externals with tags from {ctag}']
    cmd = ['git', 'tag','-a', m_tag]
    for tmsg in t_msgs:
        cmd.extend(('-m', tmsg))
    stat, oput = exe_ret(cmd)
    if stat != 0:
        msg = f'- Failed to create tag {m_tag} in EW repo'
        print(msg)
        print(f'cmd={cmd}\ncmdOut={oput}\n')
    else:
        update['ew-model']['merge']['tag'] = m_tag


def push_success(rootdir, update):
    '''If other steps were successful, perform git push on branches/tags'''
    for k, ext in update.items():
        if k == 'ew-model':
            continue
        if ext.get('repo') is None:
            continue
        if ext['merge']['stat'] == 0:
            os.chdir(rootdir / ext['local_path'])
            branch = ext['merge']['branch']
            cmd = ['git', 'push', 'origin', str(branch)]
            print('cmd={cmd}')
            stat, oput = exe_ret(cmd)
            ext['merge']['push'] = stat
            if stat != 0:
                msg = '- Push failed'
                print(msg)
                print(f'cmd={cmd}\ncmdOut={oput}\n')

            os.chdir(rootdir)

    # Push change for EW model
    m_tag = update['ew-model']['merge'].get('tag')
    if m_tag is not None:
        m_branch = update['ew-model']['merge']['branch']
        cmd = ['git', 'push', 'eworg', m_branch, m_tag]
        stat, oput = exe_ret(cmd)
        update['ew-model']['merge']['push'] = stat
        if stat != 0:
            msg = f'- Failed to push {m_branch} and {m_tag} in EW repo'
            print(msg)
            print(f'cmd={cmd}\ncmdOut={oput}\n')


def summarize_update(update):
    '''Create a formatted message with what was done'''
    print('\n\nExternal   | fetch:remote/tag/branch  | merge stat | merge branch | merge tag | pushed')
    print('           | (status 0 is success)    |            |')
    print('----------------------------------------------------')
    for k, ext in update.items():
        if k == 'ew-model':
            continue
        f_remote = f_tag = f_branch = m_stat = m_branch = m_tag = m_push = None
        fetch = ext.get('fetch')
        if fetch:
            f_remote = str(fetch.get('remote'))
            f_tag =    str(fetch.get('tag'))
            f_branch = str(fetch.get('branch'))
        else:
            continue
        merge = ext.get('merge')
        if merge:
            m_stat =   str(merge.get('stat'))
            m_branch = str(merge.get('branch'))
            m_tag =    str(merge.get('tag'))
            m_push =   str(merge.get('push'))

        print(f"{k:10} | {f_remote}/{f_tag}/{f_branch} | {m_stat} | {m_branch} | {m_tag} | {m_push}")
    print('')

    ext = update.get('ew-model')
    k = 'ew-model'
    f_remote = f_tag = f_branch = m_stat = m_branch = m_tag = m_push = None
    fetch = ext.get('fetch')
    if fetch:
        f_remote = str(fetch.get('remote'))
        f_tag =    str(fetch.get('tag'))
        f_branch = str(fetch.get('branch'))
    merge = ext.get('merge')
    if merge:
        m_stat =   str(merge.get('stat'))
        m_branch = str(merge.get('branch'))
        m_tag =    str(merge.get('tag'))
        m_push =   str(merge.get('push'))
    print(f"{k:10} | {f_remote}/_/{f_branch} | {m_stat} | {m_branch} | {m_tag} | {m_push} ")
    print('')


if __name__ == "__main__":
    args = parse_args()
    root_dir = args.root_dir
    cesm_tag = args.cesm_tag
    os.chdir(root_dir)

    print(f'Attempting to merge CESM tag {cesm_tag} into EarthWorks in directory {root_dir}')

    logging.basicConfig(filename=LOG_FILE_NAME,
                        format='%(levelname)s : %(asctime)s : %(message)s',
                        datefmt='%Y-%m-%d %H:%M:%S',
                        level=logging.DEBUG)

    ew_ext = root_dir / "Externals.cfg"
    cesm_ext = root_dir / f"Externals.{cesm_tag}.cfg"

    data_dict={}
    cont_run = setup_ewmodel(root_dir, data_dict, 'develop', cesm_tag)
    if not cont_run:
        print('- Failed to setup EWM')
        sys.exit(1)
    u_dict, ew_parser = get_update_dict(root_dir, ew_ext, cesm_ext, cesm_tag)
    if u_dict is None:
        print('- Failed to setup dictionary for update')
        sys.exit(1)
    if ew_parser is None:
        print('- Failed to setup dictionary for update')
        sys.exit(1)

    data_dict.update(u_dict)
    setup_remotes(root_dir, data_dict)
    merge_branches(root_dir, data_dict, cesm_tag)
    tag_branches(root_dir, data_dict, cesm_tag)

    update_file_externals(root_dir, data_dict, ew_parser, cesm_tag)
    # push_success(root_dir, data_dict)
    summarize_update(data_dict)
    pprinter = PrettyPrinter(indent=4)

    pprinter.pprint(data_dict)
