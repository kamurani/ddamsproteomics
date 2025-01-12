#!/usr/bin/env python3

import sys
import re
from os import environ
import argparse

from jinja2 import Template

NON_BLOCKING_MODS = {
        'GG': ['TMTpro', 'TMT6plex', 'iTRAQ8plex', 'iTRAQ4plex'],
        }

aa_weights_monoiso = { # From ExPASY
        'A': 71.03711,
        'R': 156.10111,
        'N': 114.04293,
        'D': 115.02694,
        'C': 103.00919,
        'E': 129.04259,
        'Q': 128.05858,
        'G': 57.02146,
        'H': 137.05891,
        'I': 113.08406,
        'L': 113.08406,
        'K': 128.09496,
        'M': 131.04049,
        'F': 147.06841,
        'P': 97.05276,
        'S': 87.03203,
        'T': 101.04768,
        'W': 186.07931,
        'Y': 163.06333,
        'V': 99.06841,
        'U': 150.953636,
        'O': 237.147727,
        }


class Mods:
    '''
    name is UNIMOD so tmt10plex is called TMT6plex
    name_lower is how it can be referred to by e.g. other programs e.g. OpenMS, tmt10plex
    TODO needs more attention
    '''

    def __init__(self):
        self.mods = []
        self.fixedmods = []
        self.varmods = []
        self.bymass = {}
        self.has_varmods_on_fixmod_residues = False

    def parse_msgf_modfile(self, modfile, mods_passed):
        # FIXME make sure parsing is only Unimod/mass, then set
        # fixed/var, pos, res yourself in this method
        mods_to_find = [x.lower() for x in mods_passed]
        with open(modfile) as fp:
            for line in fp:
                line = line.strip('\n')
                if line == '' or line[0] == '#' or 'NumMods' in line:
                    continue
                # TODO validate line
                msplit = line.split(',')
                name = msplit[4]
                pos = msplit[3]
                varfix = msplit[2]
                residues = set(msplit[1])
                # tmt6plex can be hidden tmt10plex, same UNIMOD mass/name
                if name.lower() == 'tmt6plex' and 'tmt10plex' in mods_to_find:
                    lowername = 'tmt10plex'
                elif name.lower() not in mods_to_find:
                    continue
                else:
                    lowername = name.lower()
                for res in residues:
                    self.mods.append({
                            'name': name, 'mass': float(msplit[0]),
                            'adjusted_mass': False,
                            'residue': res, 'var': varfix == 'opt',
                            'pos': pos, 'name_lower': lowername
                            })
        # See if user has defined own mods also
        for mtofind in mods_passed:
            moddef = mtofind.split(',')
            if len(moddef) == 5:
                # Found a custom mod defined by user
                name = moddef[4]
                pos = moddef[3]
                varfix = moddef[2]
                residues = set(moddef[1])
                for res in residues:
                    self.mods.append({
                        'name': name, 'mass': float(moddef[0]),
                        'adjusted_mass': False,
                        'residue': res, 'var': varfix == 'opt',
                        'pos': pos, 'name_lower': name.lower()
                        })

        fixedpos = {}
        for mod in self.mods:
            if mod['var']:
                self.varmods.append(mod)
            else:
                self.fixedmods.append(mod)
                res = mod['residue']
                if res in fixedpos:
                    fixedpos[res].append(mod)
                else:
                    fixedpos[res] = [mod]

        # get blocking/nonblocking mods and adjust mass (fake mass)
        for mod in self.varmods:
            nonblocked_fixed = NON_BLOCKING_MODS.get(mod['name'], []) 
            if mod['residue'] in fixedpos:
                self.has_varmods_on_fixmod_residues = True
            adjustment = 0
            for fmod in fixedpos.get(mod['residue'], []):
                if fmod['name'] not in nonblocked_fixed:
                    adjustment += fmod['mass']
            mod['adjusted_mass'] = round(-(adjustment - mod['mass']), 5)

    def get_msgf_modlines(self):
        grouped = {}
        for mod in self.mods:
            mass = self.get_mass_or_adj(mod)
            if mass not in grouped:
                grouped[mass] = [mod]
            else:
                grouped[mass].append(mod)
                check_names = set(x['name'] for x in grouped[mass])
                if len(check_names) != 1:
                    print('Cannot have two modifications of the same mass but different names')
                    sys.exit(1)

        for mass, mods in grouped.items():
            name = mods[0]['name']
            line_res = {}
            for mod in mods:
                var = int(mod['var']) # T/F -> 1/0
                mid = f'{var}__{mod["pos"]}'
                if mid not in line_res:
                    line_res[mid] = [mod['residue']]
                else:
                    line_res[mid].append(mod['residue'])
            for mid, residues in line_res.items():
                var, pos = mid.split('__')
                vf = 'opt' if int(var) else 'fix'
                yield f'{mass},{"".join(residues)},{vf},{pos},{name}'

    def get_mass_or_adj(self, mod):
        return mod['adjusted_mass'] or mod['mass']
 
    def get_luci_input_mod_line(self, mod):
        '''Doing this for each residue since the adjusted masses can differ
        per residue (due to competition)'''
        if mod['pos'] == 'N-term':
            residue = '['
        elif mod['pos'] == 'C-term':
            residue = ']'
        else:
            residue = mod['residue']
        return f'{residue} {self.get_mass_or_adj(mod)}'

    def msgfmass_mod_dict(self):
        '''Create MSGF output mass (round(x,3) ) to mod lookup'''
        mod_map = {}
        for mod in self.mods:
            try:
                mod_map[round(self.get_mass_or_adj(mod), 3)].append(mod)
            except KeyError:
                mod_map[round(self.get_mass_or_adj(mod), 3)] = [mod]
        return mod_map

    def lucimass_mod_dict(self):
        '''Create luciphor output mass (int(x+ aa) ) to mod lookup'''
        modmap = {}
        for mod in self.varmods:
            # round (, None) generates an int for luciphor
            mass = round(aa_weights_monoiso[mod['residue']] + self.get_mass_or_adj(mod))
            modmap[f'{mod["residue"]}{mass}'] = mod
        return modmap


class PSM: 
    def __init__(self):
        self.mods = []
        self.top_flr = False
        self.top_score = False
        self.lucispecid = False
        self.alt_ptm_locs = []
        self.sequence = False
        self.seq_in_scorepep_fmt = False

    def parse_msgf_peptide(self, msgfseq, msgf_mods, labileptmnames, stableptmnames):
        self.mods = []
        barepep = ''
        start = 0
        for x in re.finditer('([A-Z]){0,1}([0-9\.+\-]+)', msgfseq):
            if x.group(1) is not None:
                # mod is on a residue
                barepep = f'{barepep}{msgfseq[start:x.start()+1]}'
                residue = barepep[-1]
                sitenum = len(barepep) - 1
            else:
                # mod is on protein N-term
                residue = '['
                sitenum = -100
            # TODO cterm = 100, ']'
            start = x.end()
            for mass in re.findall('[\+\-][0-9.]+', x.group(2)):
                mod = msgf_mods[float(mass)][0] # only take first, contains enough info
                self.mods.append({
                    'site': (residue, sitenum), 'type': self.get_modtype(mod, labileptmnames, stableptmnames),
                    'mass': mod['mass'], 'name': mod['name'], 'name_lower': mod['name_lower'],
                    'adjusted_mass': mod['adjusted_mass']
                    })
        self.sequence = f'{barepep}{msgfseq[start:]}'

    def get_modtype(self, mod, labileptmnames, stableptmnames):
        if not mod['var']:
            mtype = 'fixed'
        elif mod['name_lower'] in labileptmnames:
            mtype = 'labile'
        elif mod['name_lower'] in stableptmnames:
            mtype = 'stable'
        else:
            mtype = 'variable'
        return mtype

    def parse_luciphor_peptide(self, luciline, ptms_map, labileptms, stabileptms):
        '''From a luciphor sequence, create a peptide with PTMs
        ptms_map = {f'{residue}int(79 + mass_S/T/Y)': {'name': Phospho, etc}
        '''
        self.top_flr = luciline['globalFLR']
        self.top_score = luciline['pep1score']
        self.lucispecid = luciline['specId']
        self.mods = []
        barepep, start = '', 0
        modpep = luciline['predictedPep1']
        for x in re.finditer('([A-Z]){0,1}\[([0-9]+)\]', modpep):
            if x.group(1) is not None: # check if residue (or protein N-term)
                barepep += modpep[start:x.start()+1]
            start = x.end()
            ptm = ptms_map[f'{x.group(1)}{int(x.group(2))}']
            if ptm['name_lower'] in labileptms:
                sitenum = len(barepep) - 1 if len(barepep) else -100
                residue = barepep[-1] if len(barepep) else '['
                self.mods.append({
                    'site': (residue, sitenum), 'type': self.get_modtype(ptm, labileptms, stabileptms),
                    'mass': ptm['mass'], 'name': ptm['name'], 'name_lower': ptm['name_lower'],
                    })
        self.sequence = f'{barepep}{modpep[start:]}'
        self.seq_in_scorepep_fmt = re.sub(r'([A-Z])\[[0-9]+\]', lambda x: x.group(1).lower(), modpep)

    def parse_luciphor_scores(self, scorepep, minscore):
        permut = scorepep['curPermutation']
        if permut != self.seq_in_scorepep_fmt and float(scorepep['score']) > minscore:
            self.alt_ptm_locs.append([f'{x.group()}{x.start() + 1}:{scorepep["score"]}'
                for x in re.finditer('[a-z]', permut)])

    def format_alt_ptm_locs(self):
        alt_locs = [','.join(x).upper() for x in self.alt_ptm_locs]
        return ';'.join(alt_locs) if len(alt_locs) else 'NA'

    def has_labileptms(self):
        return any(m['type'] == 'labile' for m in self.mods)
    
    def has_stableptms(self):
        return any(m['type'] == 'stable' for m in self.mods)

    def luciphor_input_sites(self):
        lucimods = []
        for m in self.mods:
            if m['type'] != 'fixed':
                lucimods.append((m['site'][1], str(m['mass'] + aa_weights_monoiso[m['site'][0]])))
        return ','.join([f'{x[0]}={x[1]}' for x in lucimods])

    def add_ptms_from_psm(self, psmmods):
        existing_mods = {m['name']: m for m in self.mods}
        for psmmod in psmmods:
            if psmmod['name'] not in existing_mods:
                self.mods.append(psmmod)

    def topptm_output(self):
        ptmsites = {}
        output_types = {'labile', 'stable'}
        for ptm in self.mods:
            if ptm['type'] not in output_types:
                continue
            site = f'{ptm["site"][0]}{ptm["site"][1] + 1}'
            try:
                ptmsites[ptm['name']].append(site)
            except KeyError:
                ptmsites[ptm['name']] = [site]
        return '_'.join([f'{p}:{",".join(s)}' for p, s in ptmsites.items()])


def create_msgf_mod_lookup():
    lookup = {}



def main():
    parser = argparse.ArgumentParser(formatter_class=argparse.RawTextHelpFormatter)
    parser.add_argument('--psmfile')
    parser.add_argument('--template')
    parser.add_argument('-o', dest='outfile')
    parser.add_argument('--lucipsms', dest='lucipsms')
    parser.add_argument('--modfile')
    parser.add_argument('--labileptms', nargs='+', default=[])
    parser.add_argument('--mods', nargs='+', default=[])
    args = parser.parse_args(sys.argv[1:])

    labileptms = [x.lower() for x in args.labileptms]
    othermods = [x.lower() for x in args.mods]
    ms2tol = environ.get('MS2TOLVALUE')
    ms2toltype = {'ppm': 1, 'Da': 0}[environ.get('MS2TOLTYPE')]

    msgfmods = Mods()
    msgfmods.parse_msgf_modfile(args.modfile, [*args.labileptms, *args.mods])
    # Prep fixed mods for luciphor template
    lucifixed = []
    for mod in msgfmods.fixedmods:
        lucifixed.append(msgfmods.get_luci_input_mod_line(mod))

    # Var mods too, and add to mass list to filter PSMs on later (all var mods must be annotated on sequence input)
    lucivar = []
    for mod in msgfmods.varmods:
        if mod['name_lower'] in labileptms:
            continue
        lucivar.append(msgfmods.get_luci_input_mod_line(mod))

    # Get PTMs from cmd line and prep for template
    # Luciphor does not work when specifying PTMs on same residue as fixed mod
    # e.g. TMT and something else, because it throws out the residues with fixed mods
    # https://github.com/dfermin/lucXor/issues/11
    target_mods, decoy_mods = [], set()
    nlosses, decoy_nloss = [], []
    for mod in msgfmods.varmods:
        if mod['name_lower'] in labileptms:
            target_mods.append(msgfmods.get_luci_input_mod_line(mod))
            decoy_mods.add(msgfmods.get_mass_or_adj(mod))
        if mod['name'] == 'Phospho':
            nlosses.append('sty -H3PO4 -97.97690')
            decoy_nloss.append('X -H3PO4 -97.07690')
            
    with open(args.template) as fp, open('luciphor_config.txt', 'w') as wfp:
        lucitemplate = Template(fp.read())
        wfp.write(lucitemplate.render(
            outfile=args.outfile,
            fixedmods=lucifixed,
            varmods=lucivar,
            ptms=target_mods,
            ms2tol=ms2tol,
            ms2toltype=ms2toltype,
            dmasses=decoy_mods,
            neutralloss=nlosses,
            decoy_nloss=decoy_nloss
            ))

    # acetyl etc? # FIXME replace double notation 229-187 in PSM table with the actual mass (42)
    # translation table needed...
    # But how to spec in luciphor, it also wants fixed/var/target mods? Does it apply fixed regardless?

    msgf_mod_map = msgfmods.msgfmass_mod_dict()
    with open(args.psmfile) as fp, open(args.lucipsms, 'w') as wfp:
        header = next(fp).strip('\n').split('\t')
        pepcol = header.index('Peptide')
        spfile = header.index('SpectraFile')
        charge = header.index('Charge')
        scan = header.index('ScanNum')
        evalue = header.index('PSM q-value')
        wfp.write('srcFile\tscanNum\tcharge\tPSMscore\tpeptide\tmodSites')
        for line in fp:
            line = line.strip('\n').split('\t')
            psm = PSM()
            psm.parse_msgf_peptide(line[pepcol], msgf_mod_map, labileptms, othermods)
            # TODO add C-terminal mods (rare)
            if psm.has_labileptms():
                wfp.write('\n{}\t{}\t{}\t{}\t{}\t{}'.format(line[spfile], line[scan], line[charge], line[evalue], psm.sequence, psm.luciphor_input_sites()))


if __name__ == '__main__':
    main()
