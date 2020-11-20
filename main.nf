#!/usr/bin/env nextflow
/*
========================================================================================
                         lehtiolab/ddamsproteomics
========================================================================================
 lehtiolab/ddamsproteomics Analysis Pipeline.
 #### Homepage / Documentation
 https://github.com/lehtiolab/ddamsproteomics
----------------------------------------------------------------------------------------
*/


def helpMessage() {
    log.info"""
    =========================================
     lehtiolab/ddamsproteomics v${workflow.manifest.version}
    =========================================
    Usage:

    The typical command for running the pipeline is as follows:

    nextflow run lehtiolab/ddamsproteomics --mzmls '*.mzML' --tdb swissprot_20181011.fa --mods 'oxidation;carbamidomethyl', --locptms 'phospho' -profile standard,docker

    Mandatory arguments:
      --mzmls                       Path to mzML files
      --mzmldef                     Alternative to --mzml: path to file containing list of mzMLs 
                                    with instrument, sample set and fractionation annotation (see docs)
      --tdb                         Path to target FASTA protein databases, can be (quoted) '/path/to/*.fa'
      -profile                      Configuration profile to use. Can use multiple (comma separated)
                                    Available: standard, conda, docker, singularity, awsbatch, test

    Options:
      --instrument                  If not using --mzmldef, use this to specify instrument type.
                                    Currently supporting 'qe' or 'velos'

      --fractions                   Fractionated samples, changes input of mzml definition and QC output
      --mods                        Modifications specified by their UNIMOD name. e.g. --mods 'oxidation;carbamidomethyl'
                                    Note that there are a limited number of modifications available, but that
                                    this list can easily be expanded in assets/msgfmods.txt
      --locptms                     As for --mods, but specify labile mods, pipeline will output false localization rate e.g.
                                    --locptms 'phospho'
      --isobaric VALUE              In case of isobaric, specify per set the type and possible denominators/sweep/intensity.
                                    In case of intensity, no ratios will be output but instead the raw PSM intensities will be
                                    median-summarized to the output features (e.g. proteins).
                                    Available types are tmtpro, tmt10plex, tmt6plex, itraq8plex, itraq4plex
                                    E.g. --isobaric 'set1:tmt10plex:126:127N set2:tmtpro:127C:131 set3:tmt10plex:sweep'
      --activation VALUE            Specify activation protocol for isobaric quantitation (NOT for identification):
                                    choose from hcd (DEFAULT), cid, etd 
      --fastadelim VALUE            FASTA header delimiter in case non-standard FASTA is used, to be used with
                                    --genefield
      --genefield VALUE             Number to determine in which field of the FASTA header (split 
                                    by --fastadelim) the gene name can be found.

      SEARCH ENGINE DETAILED PARAMETERS
      --prectol                     Precursor error for search engine (default 10ppm)
      --iso_err                     Isotope error for search engine (default -1,2)
      --frag                        Fragmentation method for search engine (default 'auto')
      --enzyme                      Enzyme used, default trypsin, pick from:
                                    unspecific, trypsin, chymotrypsin, lysc, lysn, gluc, argc, aspn, no_enzyme
      --terminicleaved              Allow only 'full', 'semi' or 'non' cleaved peptides
      --phospho                     Flag to pass in case of using phospho-enriched samples, changes MSGF protocol
      --maxmiscleav		    Maximum allowed amount of missed cleavages for MSGF+
      --minpeplen                   Minimum peptide length to search, default 7
      --maxpeplen                   Maximum peptide length to search, default 50
      --mincharge                   Minimum peptide charge search, default 2
      --maxcharge                   Maximum peptide charge search, default 6

      OUTPUT AND QUANT PARAMETERS
      --normalize                   Normalize isobaric values by median centering on channels of protein table
      --sampletable                 Path to sample annotation table in case of isobaric analysis
      --deqms                       Perform DEqMS differential expression analysis using sampletable
      --genes                       Produce gene table (i.e. gene names from Swissprot or ENSEMBL)
      --ensg                        Produce ENSG stable ID table (when using ENSEMBL db)
      --hirief                      File containing peptide sequences and their isoelectric points.
                                    An example can be found here:
                                    https://github.com/nf-core/test-datasets/blob/ddamsproteomics/testdata/formatted_known_peptides_ENSUniRefseq_TMT_predpi_20150825.txt
                                    For IEF fractionated samples, implies --fractions, enables delta pI calculation
      --onlypeptides                Do not produce protein or gene level data
      --noquant                     Do not produce isobaric or MS1 quantification data
      --noms1quant                  Do not produce MS1 quantification data
      --hardklor                    Use hardklör/krönik instead of dinosaur for MS1 quant
      --keepnapsmsquant             By default the pipeline does not use PSMs with NA in any channel for isobaric 
                                    quant summarization. Use this flag and it will keep the 
                                    (potentially more noisy) PSMs in the analysis.

      REUSING PREVIOUS DATA
      --quantlookup FILE            Use previously generated SQLite lookup database containing spectra 
                                    quantification data when e.g. re-running. Need to match exactly to the
                                    mzML files of the current run
      --targetpsmlookup FILE        When adding a new sample set to existing PSM/lookup output, a complementary run,
                                    this passes the old target PSM lookup.  Any old sets with identical names to new
                                    sets will be removed prior to adding new data.
      --decoypsmlookup FILE         As for --targetpsmlookup, but filled with earlier run decoy PSMs
      --targetpsms FILE             In a complementary run, this passes the old target PSM table. If the new set has the 
                                    same name as an old set, the old set will be removed prior to adding new data.
      --decoypsms FILE              In a complementary run, this passes the old decoy PSM table.
      --ptmpsms FILE                In a complementary run, this optionally passes the old PTM PSM table, if one runs
                                    with --locptms


    Other options:
      --outdir                      The output directory where the results will be saved
      --email                       Set this parameter to your e-mail address to get a summary e-mail with details of the run sent to you when the workflow exits
      -name                         Name for the pipeline run. If not specified, Nextflow will automatically generate a random mnemonic.

    AWSBatch options:
      --awsqueue                    The AWSBatch JobQueue that needs to be set when running on AWSBatch
      --awsregion                   The AWS Region for your AWS Batch job to run on
    """.stripIndent()
}

/*
 * SET UP CONFIGURATION VARIABLES
 */

// Show help message
if (params.help){
    helpMessage()
    exit 0
}

// Configurable variables
params.name = false
params.email = false
params.plaintext_email = false

params.mzmls = false
params.mods = false
params.locptms = false
// 50 is the minimum score for "good PTM" in HCD acc. to luciphor2 paper
// TODO evaluate if we need to set it higher
params.ptm_minscore_high = 50
params.phospho = false
params.maxvarmods = 2
params.isobaric = false
params.instrument = 'qe' // Default instrument is Q-Exactive
params.prectol = '10.0ppm'
params.iso_err = '-1,2'
params.frag = 'auto'
params.enzyme = 'trypsin'
params.terminicleaved = 'full' // semi, non
params.maxmiscleav = -1 // Default MSGF is no limit
params.minpeplen = 7
params.maxpeplen = 50
params.mincharge = 2
params.maxcharge = 6
params.psmconflvl = 0.01
params.pepconflvl = 0.01
params.fdrmethod = 'tdconcat'
params.activation = 'hcd' // Only for isobaric quantification
params.outdir = 'results'
params.normalize = false
params.genes = false
params.ensg = false
params.fastadelim = false
params.genefield = false
params.quantlookup = false
params.fractions = false
params.hirief = false
params.onlypeptides = false
params.noquant = false
params.noms1quant = false
params.hardklor = false
params.keepnapsmsquant = false
params.sampletable = false
params.deqms = false
params.targetpsmlookup = false
params.decoypsmlookup = false
params.targetpsms = false
params.decoypsms = false
params.ptmpsms = false

// Validate and set file inputs
fractionation = (params.hirief || params.fractions)

// Files which are not standard can be checked here
if (params.hirief && !file(params.hirief).exists()) exit 1, "Peptide pI data file not found: ${params.hirief}"
if (params.sampletable) {
  sampletable = file(params.sampletable)
  if( !sampletable.exists() ) exit 1, "Sampletable file not found: ${params.sampletable}"
} else {
  sampletable = 0
}

if (params.targetpsmlookup && params.decoypsmlookup && params.targetpsms && params.decoypsms) {
  if (params.quantlookup) exit 1, "When specifying a complementary you may not pass --quantlookup"
  complementary_run = true
  prev_results = Channel
    .fromPath([params.targetpsmlookup, params.decoypsmlookup, params.targetpsms, params.decoypsms, params.ptmpsms ? params.ptmpsms : 'NA'])
    .toList()
} else if (params.targetpsmlookup || params.decoypsmlookup || params.targetpsms || params.decoypsms || params.ptmpsms) {
  exit 1, "When specifying a complementary run you need to pass all of --targetpsmlookup, --decoypsmlookup, --targetpsms, --decoypsms"
} else {
  complementary_run = false
  prev_results = Channel.empty()
}

output_docs = file("$baseDir/docs/output.md")

// set constant variables
accolmap = [peptides: 13, proteins: 15, ensg: 18, genes: 19]
acctypes = ['proteins']
if (params.onlypeptides) {
  acctypes = []
} else {
  if (params.ensg) {
  acctypes = acctypes.plus('ensg')
  }
  if (params.genes) {
  acctypes = acctypes.plus('genes')
  }
}

availProcessors = Runtime.runtime.availableProcessors()

// parse inputs that combine to form values or are otherwise more complex.

// Isobaric input example: --isobaric 'set1:tmt10plex:127N:128N set2:tmtpro:sweep set3:itraq8plex:intensity'
isop = params.isobaric ? params.isobaric.tokenize(' ') : false
setisobaric = isop ? isop.collect() {
  y -> y.tokenize(':')
}.collectEntries() {
  x-> [x[0], x[1]]
} : false
// FIXME add non-isobaric sets here if we have any mixed-in?
setdenoms = isop ? isop.collect() {
  y -> y.tokenize(':')
}.collectEntries() {
  x-> [x[0], x[2..-1]]
} : false

luciphor_ptms = params.locptms ? params.locptms.tokenize(';') : false

normalize = (!params.noquant && (params.normalize || params.deqms) && params.isobaric)

// AWSBatch sanity checking
if(workflow.profile == 'awsbatch'){
    if (!params.awsqueue || !params.awsregion) exit 1, "Specify correct --awsqueue and --awsregion parameters on AWSBatch!"
    if (!workflow.workDir.startsWith('s3') || !params.outdir.startsWith('s3')) exit 1, "Specify S3 URLs for workDir and outdir parameters on AWSBatch!"
}


// Has the run name been specified by the user?
//  this has the bonus effect of catching both -name and --name
custom_runName = params.name
if( !(workflow.runName ==~ /[a-z]+_[a-z]+/) ){
  custom_runName = workflow.runName
}

// Check workDir/outdir paths to be S3 buckets if running on AWSBatch
// related: https://github.com/nextflow-io/nextflow/issues/813
if( workflow.profile == 'awsbatch') {
    if(!workflow.workDir.startsWith('s3:') || !params.outdir.startsWith('s3:')) exit 1, "Workdir or Outdir not on S3 - specify S3 Buckets for each to run on AWSBatch!"
}


// Header log info
log.info """=======================================================
                                          ,--./,-.
          ___     __   __   __   ___     /,-._.--~\'
    |\\ | |__  __ /  ` /  \\ |__) |__         }  {
    | \\| |       \\__, \\__/ |  \\ |___     \\`-._,-`-,
                                          `._,._,\'

lehtiolab/ddamsproteomics v${workflow.manifest.version}"
======================================================="""
def summary = [:]
summary['Pipeline Name']  = 'lehtiolab/ddamsproteomics'
summary['Pipeline Version'] = workflow.manifest.version
summary['Run Name']     = custom_runName ?: workflow.runName
summary['mzMLs']        = params.mzmls
summary['Target DB']    = params.tdb
summary['Sample annotations'] = params.sampletable
summary['Modifications'] = params.mods
summary['PTMs'] = params.locptms
summary['Phospho enriched'] = params.phospho
summary['Instrument'] = params.mzmldef ? 'Set per mzML file in mzml definition file' : params.instrument
summary['Precursor tolerance'] = params.prectol
summary['Isotope error'] = params.iso_err
summary['Fragmentation method'] = params.frag
summary['Enzyme'] = params.enzyme
summary['Allowed peptide termini cleavage'] = params.terminicleaved
summary['Allowed amount of missed cleavages'] = params.maxmiscleav
summary['Minimum peptide length'] = params.minpeplen
summary['Maximum peptide length'] = params.maxpeplen
summary['Minimum peptide charge'] = params.mincharge
summary['Maximum peptide charge'] = params.maxcharge
summary['FDR method'] = params.fdrmethod
summary['Isobaric tags'] = params.isobaric
summary['Isobaric activation'] = params.activation
summary['Isobaric normalization'] = params.normalize
summary['Output genes'] = params.genes
summary['Output ENSG IDs'] = params.ensg
summary['Custom FASTA delimiter'] = params.fastadelim 
summary['Custom FASTA gene field'] = params.genefield
summary['Premade quant data SQLite'] = params.quantlookup
summary['Previous run target results SQLite'] = params.targetpsmlookup
summary['Previous run decoy results SQLite'] = params.decoypsmlookup
summary['Previous run target PSMs'] = params.targetpsms
summary['Previous run decoy PSMs'] = params.decoypsms
summary['Fractionated sample'] = fractionation
summary['HiRIEF pI peptide data'] = params.hirief 
summary['Only output peptides'] = params.onlypeptides
summary['Do not quantify'] = params.noquant
summary['Perform DE analysis'] = params.deqms
summary['Max Memory']   = params.max_memory
summary['Max CPUs']     = params.max_cpus
summary['Max Time']     = params.max_time
summary['Output dir']   = params.outdir
summary['Working dir']  = workflow.workDir
summary['Container Engine'] = workflow.containerEngine
if(workflow.containerEngine) summary['Container'] = workflow.container
summary['Current home']   = "$HOME"
summary['Current user']   = "$USER"
summary['Current path']   = "$PWD"
summary['Working dir']    = workflow.workDir
summary['Output dir']     = params.outdir
summary['Script dir']     = workflow.projectDir
summary['Config Profile'] = workflow.profile
if(workflow.profile == 'awsbatch'){
   summary['AWS Region'] = params.awsregion
   summary['AWS Queue'] = params.awsqueue
}
if(params.email) summary['E-mail Address'] = params.email
log.info summary.collect { k,v -> "${k.padRight(15)}: $v" }.join("\n")
log.info "========================================="


def create_workflow_summary(summary) {

    def yaml_file = workDir.resolve('workflow_summary_mqc.yaml')
    yaml_file.text  = """
    id: 'lehtiolab-ddamsproteomics-summary'
    description: " - this information is collected when the pipeline is started."
    section_name: 'lehtiolab/ddamsproteomics Workflow Summary'
    section_href: 'https://github.com/lehtiolab/ddamsproteomics'
    plot_type: 'html'
    data: |
        <dl class=\"dl-horizontal\">
${summary.collect { k,v -> "            <dt>$k</dt><dd><samp>${v ?: '<span style=\"color:#999999;\">N/A</a>'}</samp></dd>" }.join("\n")}
        </dl>
    """.stripIndent()

   return yaml_file
}


/*
 * Parse software version numbers
 */
process get_software_versions {

    publishDir "${params.outdir}", mode: 'copy'

    output:
    file 'software_versions.yaml' into software_versions_qc

    script:
    """
    echo $workflow.manifest.version > v_pipeline.txt
    echo $workflow.nextflow.version > v_nextflow.txt
    msgf_plus | head -n2 | grep Release > v_msgf.txt
    dinosaur | head -n2 | grep Dinosaur > v_dino.txt || true
    hardklor | head -n1 > v_hk.txt || true
    kronik | head -n2 | tr -cd '[:alnum:]._-' > v_kr.txt
    #luciphor2 |& grep Version > v_luci.txt # incorrect version from binary (2014), echo below
    echo Version: 2020_04_03 > v_luci.txt # deprecate when binary is correct
    percolator -h |& head -n1 > v_perco.txt || true
    msstitch --version > v_mss.txt
    IsobaricAnalyzer |& grep Version > v_openms.txt || true
    Rscript <(echo "packageVersion('DEqMS')") > v_deqms.txt
    scrape_software_versions.py > software_versions.yaml
    """
}

if (workflow.profile.tokenize(',').intersect(['test', 'test_nofrac'])) { 
  // Profile 'test' delivers mzmlPaths
  Channel
    .from(params.mzmlPaths)
    .set { mzml_in }
}
else if (!params.mzmldef) {
  Channel
    .fromPath(params.mzmls)
    .map { it -> [it, params.instrument, 'NA'] }
    .set { mzml_in }
} else {
  Channel
    .from(file("${params.mzmldef}").readLines())
    .map { it -> it.tokenize('\t') }
    .set { mzml_in }
}


def or_na(it, length){
    return it.size() > length ? it[length] : 'NA'
}


process createTargetDecoyFasta {
 
  input:
  path(tdb) from Channel.fromPath(params.tdb).toList()

  output:
  file('db.fa') into concatdb
  set file('tdb'), file("decoy.fa") into bothdbs

  script:
  """
  cat ${tdb.collect() { "\"${it}\"" }.join(' ')} > tdb
  msstitch makedecoy -i tdb -o decoy.fa --scramble tryp_rev --ignore-target-hits
  cat tdb decoy.fa > db.fa
  """
}

bothdbs.into { psmdbs; fdrdbs }

// Parse mzML input to get files and sample names etc
// get setname, sample name (baseName), input mzML file. 
// Set platename to samplename if not specified. 
// Set fraction name to NA if not specified
mzml_in
  .tap { mzmlfiles_counter; mzmlfiles_qlup_sets } // for counting-> timelimits; getting sets from supplied lookup
  .map { it -> [it[2], file(it[0]).baseName, file(it[0]), it[1], (it.size() > 3 ? it[3] : it[2]), or_na(it, 4)] }
  .tap { mzmlfiles; mzml_luciphor; mzml_quant }
  .combine(concatdb)
  .set { mzml_msgf }

/*
* Step 1: Extract quant data from peptide spectra
*/

process quantifySpectra {
  when: !params.quantlookup && !params.noquant

  input:
  set val(setname), val(sample), file(infile), val(instr), val(platename), val(fraction) from mzml_quant
  file(hkconf) from Channel.fromPath("$baseDir/assets/hardklor.conf").first()

  output:
  set val(sample), val(infile.name) into sample_mzmlfn
  set val(sample), file("${infile.baseName}.features.tsv") optional true into dino_out 
  set val(sample), file("${sample}.kr") optional true into kronik_out 
  set val(sample), file("${infile}.consensusXML") optional true into isobaricxml

  script:
  activationtype = [hcd:'High-energy collision-induced dissociation', cid:'Collision-induced dissociation', etd:'Electron transfer dissociation'][params.activation]
  isobtype = setisobaric && setisobaric[setname] ? setisobaric[setname] : false
  isobtype = isobtype == 'tmtpro' ? 'tmt16plex' : isobtype
  plextype = isobtype ? isobtype.replaceFirst(/[0-9]+plex/, "") : 'false'
  massshift = [tmt:0.0013, itraq:0.00125, false:0][plextype]
  """
  # Dinosaur is first choice for MS1 quant
  ${!params.noms1quant && !params.hardklor ? "dinosaur --concurrency=${task.cpus * params.threadspercore} \"${infile}\"" : ''}
  # Hardklor/Kronik can be used as a backup, using --hardklor
  ${!params.noms1quant && params.hardklor ? "hardklor <(cat $hkconf <(echo \"$infile\" hardklor.out)) && kronik -c 5 -d 3 -g 1 -m 8000 -n 600 -p 10 hardklor.out ${sample}.kr" : ''}

  ${isobtype ? "IsobaricAnalyzer -type $isobtype -in $infile -out \"${infile}.consensusXML\" -extraction:select_activation \"$activationtype\" -extraction:reporter_mass_shift $massshift -extraction:min_precursor_intensity 1.0 -extraction:keep_unannotated_precursor true -quantification:isotope_correction true" : ''}
  """
}


// Collect all mzMLs into single item to pass to lookup builder and spectra counter
mzmlfiles
  .toList()
  .map { it.sort( {a, b -> a[1] <=> b[1]}) } // sort on sample for consistent .sh script in -resume
  .map { it -> [it.collect() { it[0] }, it.collect() { it[2] }, it.collect() { it[4] } ] } // lists: [sets], [mzmlfiles], [plates]
  .into { mzmlfiles_all; mzmlfiles_all_count; mzmlfiles_comp }

mzmlfiles_counter
  .count()
  .subscribe { println "$it mzML files in analysis" }
  .into { mzmlcount_psm; mzmlcount_percolator }



process complementSpectraLookupCleanPSMs {

  when: complementary_run

  input:
  set val(in_setnames), path(mzmlfiles), val(platenames) from mzmlfiles_comp
  set path(tlup), path(dlup), path(tpsms), path(dpsms), path(ptmpsms) from prev_results

  output:
  set path('t_cleaned_psms.txt'), path('d_cleaned_psms.txt') into cleaned_psms
  set path('target_db.sqlite'), path('decoy_db.sqlite') into complemented_speclookup 
  path 'cleaned_ptmpsms' into cleaned_ptmpsms optional true
  file('all_setnames') into oldnewsets 
  
  script:
  setnames = in_setnames.unique(false)
  """
  # If this is an addition to an old lookup, copy it and extract set names
  cp "${tlup}" target_db.sqlite && sqlite3 target_db.sqlite "SELECT set_name FROM biosets" > old_setnames
  cp "${dlup}" decoy_db.sqlite
  # If adding to old lookup: grep new setnames in old and run msstitch deletesets if they match
  if grep -f old_setnames <(echo ${setnames.join('\n')} )
    then
      msstitch deletesets -i "${tpsms}" -o t_cleaned_psms.txt --dbfile target_db.sqlite --setnames "${setnames.join(' ')}"
      msstitch deletesets -i "${dpsms}" -o d_cleaned_psms.txt --dbfile decoy_db.sqlite --setnames "${setnames.join(' ')}"
      ${params.ptmpsms ? "msstitch deletesets -i \"${ptmpsms}\" -o cleaned_ptmpsms.txt --setnames ${setnames.join(' ')}" : ''}
    else
      mv "${tpsms}" t_cleaned_psms.txt
      mv "${dpsms}" d_cleaned_psms.txt
      ${params.ptmpsms ? "mv \"${ptmpsms}\" cleaned_ptmpsms.txt" : ''}
  fi
  msstitch storespectra --spectra ${mzmlfiles.join(' ')} --setnames ${in_setnames.join(' ')} --dbfile target_db.sqlite
  copy_spectra.py target_db.sqlite decoy_db.sqlite ${setnames.join(' ')}
  cat old_setnames <(echo ${setnames.join('\n')}) | sort -u > all_setnames
  """
}


process createNewSpectraLookup {

  when: !params.quantlookup && !complementary_run

  input:
  set val(setnames), file(mzmlfiles), val(platenames) from mzmlfiles_all

  output:
  set path('target_db.sqlite'), path('decoy_db.sqlite') into newspeclookup 
  val(uni_setnames) into allsetnames

  script:
  uni_setnames = setnames.unique(false)
  """
  msstitch storespectra --spectra ${mzmlfiles.join(' ')} --setnames ${setnames.join(' ')} -o target_db.sqlite
  ln -s target_db.sqlite decoy_db.sqlite
  """
}

if (complementary_run) {
  oldnewsets
    .splitText()
    .map { it -> it.replaceAll('\n', '') }
    .toList()
    .set { allsetnames }
  cleaned_psms
    .flatMap { it -> [['target', it[0]], ['decoy', it[1]]] }
    .set { td_oldpsms }
} else {
  // if not using this youll have a combine on an open channel without
  // anything from complement cleaner. Will not run createPTMLookup then
  cleaned_ptmpsms = Channel.value('NA')
}

// Collect all MS1 dinosaur/kronik output for quant lookup building process
dino_out
  .concat(kronik_out)
  .set { ms1_out }

sample_mzmlfn
  .join(ms1_out, remainder: true)
  .join(isobaricxml, remainder: true)
  .toList()
  .map { it.sort({a, b -> a[0] <=> b[0]}) }
  .transpose()
  .toList()
  .set { quantfiles_sets }


// Need to populate channels depending on if a pre-made quant lookup has been passed
// even if not needing quant (--noquant) this is necessary or NF will error
newspeclookup
  .concat(complemented_speclookup)
  .tap { prespectoquant }
  .map { it -> it[0] } // get only target lookup
  .into { ptm_lookup_in; countlookup }

if (params.noquant && !params.quantlookup) {
  // Noquant, fresh spectra lookup scenario
  prespectoquant
    .flatMap { it -> [[it[0], 'target'], [it[1], 'decoy']] }
    .set { specquant_lookups }
   spectoquant = Channel.empty()
} else if (params.quantlookup) {
  // Runs with a premade quant lookup eg from previous search
  spectoquant = Channel.empty()
  Channel
    .fromPath(params.quantlookup)
    .flatMap { it -> [[it, 'target'], [it, 'decoy']] }
    .tap { specquant_lookups }
    .filter { it[1] == 'target' }
    .map { it -> it[0] }
    .into { ptm_lookup_in; countlookup }
  mzmlfiles_qlup_sets
    .map { it -> it[2] } 
    .unique()
    .toList()
    .set { allsetnames }
} else {
  prespectoquant.set { spectoquant }
}


// Set names are first item in input lists, collect them for PSM tables and QC purposes
allsetnames 
  .into { setnames_featqc; setnames_psms; setnames_psmqc }


process quantLookup {

  publishDir "${params.outdir}", mode: 'copy', overwrite: true, saveAs: {it == 'target.sqlite' ? 'quant_lookup.sql' : null }

  when: !params.quantlookup && !params.noquant

  input:
  set path(tlookup), path(dlookup) from spectoquant
  set val(samples), val(mzmlnames), file(ms1fns), file(isofns) from quantfiles_sets

  output:
  set path('target.sqlite'), path(dlookup) into newquantlookup

  script:
  """
  # SQLite lookup needs copying to not modify the input file which would mess up a rerun with -resume
  cat $tlookup > target.sqlite
  msstitch storequant --dbfile target.sqlite --spectra ${mzmlnames.join(' ')}  \
    ${!params.noms1quant ? "--mztol 20.0 --mztoltype ppm --rttol 5.0 ${params.hardklor ? "--kronik ${ms1fns.join(' ')}" : "--dinosaur ${ms1fns.join(' ')}"}" : ''} \
    ${params.isobaric ? "--isobaric ${isofns.join(' ')}" : ''}
  """
}


if (!params.quantlookup && !params.noquant) {
  newquantlookup
    .flatMap { it -> [[it[0], 'target'], [it[1], 'decoy']] }
    .set { specquant_lookups }
} 

mzmlfiles_all_count
  .merge(countlookup)
  .set { specfilein }


process countMS2perFile {

  input:
  set val(setnames), file(mzmlfiles), val(platenames), file(speclookup) from specfilein

  output:
  set val(setnames), file(mzmlfiles), val(platenames), file('amount_spectra_files') into specfilems2

  script:
  """
  sqlite3 $speclookup "SELECT mzmlfilename, COUNT(*) FROM mzml JOIN mzmlfiles USING(mzmlfile_id) JOIN biosets USING(set_id) GROUP BY mzmlfilename" > amount_spectra_files
  """
}


if (fractionation) { 
  specfilems2.set { scans_platecount }
} else {
  specfilems2
    .map { it -> [it[3], ['noplates']] }
    .into { scans_platecount; scans_result }
}


process countMS2sPerPlate {

  publishDir "${params.outdir}", mode: 'copy', overwrite: true 
  when: fractionation

  input:
  set val(setnames), file(mzmlfiles), val(platenames), file('nr_spec_per_file') from scans_platecount

  output:
  set file('scans_per_plate'), val(splates) into scans_perplate

  script:
  splates = [setnames, platenames].transpose().collect() { "${it[0]}_${it[1]}" }
  """
  #!/usr/bin/env python
  platesets = [\"${splates.join('", "')}\"]
  platescans = {p: 0 for p in platesets}
  fileplates = {fn: p for fn, p in zip([\"${mzmlfiles.join('", "')}\"], platesets)}
  with open('nr_spec_per_file') as fp:
      for line in fp:
          fn, scans = line.strip('\\n').split('|')
          platescans[fileplates[fn]] += int(scans)
  with open('scans_per_plate', 'w') as fp:
      for plate, scans in platescans.items():
          fp.write('{}\\t{}\\n'.format(plate, scans))
  """
}

if (fractionation) {
  scans_perplate.set { scans_result }
}

/*
* Step 2: Identify peptides
*/

process msgfPlus {
  cpus = availProcessors < 4 ? availProcessors : 4

  input:
  set val(setname), val(sample), file(x), val(instrument), val(platename), val(fraction), file(db) from mzml_msgf

  output:
  set val(setname), val(sample), file("${sample}.mzid"), file("${sample}.mzid.tsv") into mzids
  
  script:
  isobtype = setisobaric && setisobaric[setname] ? setisobaric[setname] : false
  // protcol 0 is automatic, msgf checks in mod file, TMT should be run with 1
  // see at https://github.com/MSGFPlus/msgfplus/issues/19
  msgfprotocol = params.phospho ? setisobaric[setname][0..4] == 'itraq' ? 3 : 1 : 0
  msgfinstrument = [velos:1, qe:3, false:0][instrument]
  fragmeth = [auto:0, cid:1, etd:2, hcd:3, uvpd:4][params.frag]
  enzyme = params.enzyme.indexOf('-') > -1 ? params.enzyme.replaceAll('-', '') : params.enzyme
  enzyme = [unspecific:0, trypsin:1, chymotrypsin: 2, lysc: 3, lysn: 4, gluc: 5, argc: 6, aspn:7, no_enzyme:9][enzyme]
  ntt = [full: 2, semi: 1, non: 0][params.terminicleaved]

  """
  create_modfile.py ${params.maxvarmods} "${params.msgfmods}" "${params.mods}${isobtype ? ";${isobtype}" : ''}${params.locptms ? ";${params.locptms}" : ''}"
  msgf_plus -Xmx8G -d $db -s $x -o "${sample}.mzid" -thread ${task.cpus * params.threadspercore} -mod "mods.txt" -tda 0 -maxMissedCleavages $params.maxmiscleav -t ${params.prectol}  -ti ${params.iso_err} -m ${fragmeth} -inst ${msgfinstrument} -e ${enzyme} -protocol ${msgfprotocol} -ntt ${ntt} -minLength ${params.minpeplen} -maxLength ${params.maxpeplen} -minCharge ${params.mincharge} -maxCharge ${params.maxcharge} -n 1 -addFeatures 1
  msgf_plus -Xmx3500M edu.ucsd.msjava.ui.MzIDToTsv -i "${sample}.mzid" -o out.tsv
  awk -F \$'\\t' '{OFS=FS ; print \$0, "Biological set" ${fractionation ? ', "Strip", "Fraction"' : ''}}' <( head -n+1 out.tsv) > "${sample}.mzid.tsv"
  awk -F \$'\\t' '{OFS=FS ; print \$0, "$setname" ${fractionation ? ", \"$platename\", \"$fraction\"" : ''}}' <( tail -n+2 out.tsv) >> "${sample}.mzid.tsv"
  rm ${db.baseName.replaceFirst(/\.fasta/, "")}.c*
  """
}


mzids
  .groupTuple()
  //.map { it -> [it[1], it[2]] }
  .set { mzids_2pin }


process percolator {

  input:
  set val(setname), val(samples), file(mzids), file(tsvs) from mzids_2pin
  val(mzmlcount) from mzmlcount_percolator

  output:
  //set val(setname), file('perco.xml') into percolated
  set path('target.tsv'), val('target') into tmzidtsv_perco
  set path('decoy.tsv'), val('decoy') into dmzidtsv_perco

  script:
  """
  ${mzids.collect() { "echo $it >> metafile" }.join('&&')}
  msgf2pin -o percoin.tsv -e ${params.enzyme} -P "decoy_" metafile
  percolator -j percoin.tsv -X perco.xml -N 500000 --decoy-xml-output
  mkdir outtables
  msstitch perco2psm --perco perco.xml -d outtables -i ${tsvs.collect() { "'$it'" }.join(' ')} --mzids ${mzids.collect() { "'$it'" }.join(' ')} --filtpsm ${params.psmconflvl} --filtpep ${params.pepconflvl}
  msstitch concat -i outtables/* -o psms
  msstitch split -i psms --splitcol \$(head -n1 psms | tr '\t' '\n' | grep -n ^TD\$ | cut -f 1 -d':')
  """
}

// Collect percolator data of target/decoy and feed into PSM table creation
tmzidtsv_perco
  .concat(dmzidtsv_perco)
  .groupTuple(by: 1) // group by TD
  .join(specquant_lookups, by: 1) // join on TD
  .combine(psmdbs)
  .set { psmswithout_oldpsms }
if (complementary_run) {
  psmswithout_oldpsms.join(td_oldpsms).set { prepsm }
} else {
  psmswithout_oldpsms.set { prepsm }
}

/*
* Step 3: Post-process peptide identification data
*/

hiriefpep = params.hirief ? Channel.fromPath([params.hirief, params.hirief]) : Channel.value(['NA', 'NA'])

process createPSMTable {

  publishDir "${params.outdir}", mode: 'copy', overwrite: true, saveAs: {["target_psmlookup.sql", "decoy_psmlookup.sql", "target_psmtable.txt", "decoy_psmtable.txt"].contains(it) ? it : null}

  input:
  set val(td), path('psms?'), path('lookup'), path(tdb), path(ddb), file(cleaned_oldpsms) from prepsm
  file(trainingpep) from hiriefpep
  val(mzmlcount) from mzmlcount_psm
  val(setnames) from setnames_psms

  output:
  set val(td), file("${outpsms}") into psm_result
  set val(td), file({setnames.collect() { "${it}.tsv" }}) optional true into setpsmtables
  set val(td), file("${psmlookup}") into psmlookup
  file('warnings') optional true into psmwarnings

  script:
  psmlookup = "${td}_psmlookup.sql"
  outpsms = "${td}_psmtable.txt"

  quant = !params.noquant && td == 'target'
  """
  msstitch concat -i psms* -o psms.txt
  tail -n+2 psms.txt | grep . || (echo "No ${td} PSMs made the combined PSM / peptide FDR cutoff (${params.psmconflvl} / ${params.pepconflvl})" && exit 1)
  # SQLite lookup needs copying to not modify the input file which would mess up a rerun with -resume
  cat lookup > $psmlookup
  sed 's/\\#SpecFile/SpectraFile/' -i psms.txt
  msstitch psmtable -i psms.txt --dbfile $psmlookup --addmiscleav -o psmsrefined --spectracol 1 \
    ${params.onlypeptides ? '' : "--fasta \"${td == 'target' ? "${tdb}" : "${ddb}"}\" --genes"} \
    ${quant ? "${!params.noms1quant ? '--ms1quant' : ''} ${params.isobaric ? '--isobaric' : ''}" : ''} \
    ${!params.onlypeptides ? '--proteingroup' : ''} \
    ${complementary_run ? "--oldpsms ${cleaned_oldpsms}" : ''}
  sed 's/\\#SpecFile/SpectraFile/' -i psmsrefined
  ${params.hirief && td == 'target' ? "echo \'${groovy.json.JsonOutput.toJson(params.strips)}\' >> strip.json && peptide_pi_annotator.py -i $trainingpep -p psmsrefined --o $outpsms --stripcolpattern Strip --pepcolpattern Peptide --fraccolpattern Fraction --stripdef strip.json --ignoremods \'*\'": "mv psmsrefined ${outpsms}"} 
  msstitch split -i ${outpsms} --splitcol bioset
  ${setnames.collect() { "test -f '${it}.tsv' || echo 'No ${td} PSMs found for set ${it}' >> warnings" }.join(' && ') }
  """
}

// Collect setnames and merge with PSM tables for peptide table creation
def listify(it) {
  return it instanceof java.util.List ? it : [it]
}
setpsmtables
  .map { it -> [it[0], listify(it[1])] }
  .map{ it -> [it[0], it[1].collect() { it.baseName.replaceFirst(/\.tsv$/, "") }, it[1]]}
  .transpose()
  .tap { psm_pep }
  .filter { it -> it[0] == 'target' }
  .map { it -> it[1..2] }
  .set { psm_ptm }

mzml_luciphor
  .map { it -> [it[0], it[2]] } // only need setname and mzml
  .groupTuple()
  .join(psm_ptm)
  .set { psm_luciphor }


process luciphorPTMLocalizationScoring {

  cpus = availProcessors < 4 ? availProcessors : 4
  when: params.locptms

  input:
  set val(setname), file(mzmls), file('psms') from psm_luciphor

  output:
  set val(setname), file('ptms.txt') into luciphor_all

  script:
  denom = !params.noquant && setdenoms ? setdenoms[setname] : false
  specialdenom = denom && (denom[0] == 'sweep' || denom[0] == 'intensity')
  isobtype = setisobaric && setisobaric[setname] ? setisobaric[setname] : ''
  """
  export MZML_PATH=\$(pwd)
  export MINPSMS=${params.minpsms_luciphor}
  export ALGO=${params.activation == 'hcd' ? '1' : '0'}
  export MAXPEPLEN=${params.maxpeplen}
  export MAXCHARGE=${params.maxcharge}
  export THREAD=${task.cpus * params.threadspercore}
  export MS2TOLVALUE=0.025
  export MS2TOLTYPE=Da
  cat "$baseDir/assets/luciphor2_input_template.txt" | envsubst > lucinput.txt
  luciphor_prep.py psms lucinput.txt "${params.msgfmods}" "${params.mods}${isobtype ? ";${isobtype}" : ''}" "${params.locptms}" luciphor.out
  luciphor2 luciphor_config.txt
  luciphor_parse.py ${params.ptm_minscore_high} ptms.txt "${params.msgfmods}" "${params.locptms};${params.mods}"
  """
}

// Sort to be able to resume
luciphor_all
  .toList()
  .map { it.sort( {a, b -> a[0] <=> b[0]}) } // sort on setname
  .transpose()
  .toList()
  .combine(cleaned_ptmpsms)
  .set { lucptmfiles_to_lup }


process createPTMLookup {
  publishDir "${params.outdir}", mode: 'copy', overwrite: true, saveAs: {it == ptmtable ? ptmtable: null}

  when: params.locptms

  input:
  tuple val(setnames), file('ptms?'), file(cleaned_oldptms) from lucptmfiles_to_lup
  file(ptmlup) from ptm_lookup_in

  output:
  path(ptmtable) into features_out
  path 'ptmlup.sql' into ptmlup
  path({setnames.collect() { "${it}.tsv" }}) optional true into setptmtables
  //set val(setnames), file({setnames.collect() { "${it}.tsv" }}) optional true into setptmtables
  path 'warnings' optional true into ptmwarnings

  script:
  ptmtable = "ptm_psmtable.txt"
  """
  msstitch concat -i ptms* -o "${ptmtable}"
  cat "${ptmlup}" > ptmlup.sql
  msstitch psmtable -i "${ptmtable}" --dbfile ptmlup.sql -o ptmtable_read \
    ${complementary_run ? "--oldpsms ${cleaned_oldpsms}" : ''} --spectracol 1
  msstitch split -i "${ptmtable}" --splitcol bioset
  ${setnames.collect() { "test -f '${it}.tsv' || echo 'No PTMs found for set ${it}' >> warnings" }.join(' && ') }
  """
}


setptmtables
  .map { it -> listify(it) }
  .map{ it -> [it.collect() { it.baseName.replaceFirst(/\.tsv$/, "") }, it]} // setname from file setA.tsv
  .transpose()
  .set { ptm2peps }


process PTMPeptides {

  input:
  tuple val(setname), path('ptms.txt') from ptm2peps

  output:
  tuple val(setname), path(peptable) into ptmpeps

  script:
  denom = !params.noquant && setdenoms ? setdenoms[setname] : false
  specialdenom = denom && (denom[0] == 'sweep' || denom[0] == 'intensity')
  peptable = "${setname}_ptm_peptides.txt"
  """
  msstitch peptides -i "ptms.txt" -o "${peptable}" --scorecolpattern svm --spectracol 1 \
    ${!params.noquant ? "${!params.noms1quant ? '--ms1quantcolpattern area' : ''} ${setisobaric && setisobaric[setname] ? '--isobquantcolpattern plex --minint 0.1' : ''}" : ''} \
    ${!params.noquant && setisobaric && setisobaric[setname] && params.keepnapsmsquant ? '--keep-psms-na-quant' : ''} \
    ${denom && denom[0] == 'sweep' ? '--mediansweep --logisoquant': ''} \
    ${denom && denom[0] == 'intensity' ? '--medianintensity' : ''} \
    ${denom && !specialdenom ? "--logisoquant --denompatterns ${setdenoms[setname].join(' ')}": ''}
  """
}

ptmpeps
  .toList()
  .map { it.sort( {a, b -> a[0] <=> b[0]}) } // sort on setname
  .transpose()
  .toList()
  .combine(ptmlup)
  .set { ptmpeps2merge }
  

process mergePTMPeps {
  publishDir "${params.outdir}", mode: 'copy', overwrite: true

  input:
  tuple val(setnames), path(peptides), path('ptmlup.sql') from ptmpeps2merge

  output:
  file 'ptm_peptidetable.txt'

  script:
  """
  cat ptmlup.sql > pepptmlup.sql
  msstitch merge -i ${peptides.join(' ')} --setnames ${setnames.join(' ')} --dbfile pepptmlup.sql -o mergedtable --no-group-annotation \
    --fdrcolpattern 'FLR\$' \
    ${!params.noquant && !params.noms1quant ? "--ms1quantcolpattern area" : ''} \
    ${!params.noquant && setisobaric ? "--isobquantcolpattern plex" : ''}
  head -n1 mergedtable | sed 's/q-value/FLR/g' > ptm_peptidetable.txt
  tail -n+2 mergedtable | sort -k1b,1 >> ptm_peptidetable.txt
  """
}

process makePeptides {
  input:
  set val(td), val(setname), file('psms') from psm_pep
  
  output:
  set val(setname), val(td), file(psms), file("${setname}_peptides") into prepgs_in
  set val(setname), val('peptides'), val(td), file("${setname}_peptides") into peptides_out
  file('warnings') optional true into pepwarnings
  set val(setname), path(normfactors) optional true into pepnormfac

  script:
  quant = !params.noquant && td == 'target'
  denom = quant && setdenoms ? setdenoms[setname] : false
  specialdenom = denom && (denom[0] == 'sweep' || denom[0] == 'intensity')
  normfactors = "${setname}_normfacs"
  """
  # Create peptide table from PSM table, picking best scoring unique peptides
  msstitch peptides -i psms -o "${setname}_peptides" --scorecolpattern svm --spectracol 1 --modelqvals \
    ${quant ? "${!params.noms1quant ? '--ms1quantcolpattern area' : ''} ${setisobaric && setisobaric[setname] ? '--isobquantcolpattern plex --minint 0.1' : ''}" : ''} \
    ${quant && setisobaric && setisobaric[setname] && params.keepnapsmsquant ? '--keep-psms-na-quant' : ''} \
    ${denom && denom[0] == 'sweep' ? '--mediansweep --logisoquant' : ''} \
    ${denom && denom[0] == 'intensity' ? '--medianintensity' : ''} \
    ${denom && !specialdenom ? "--logisoquant --denompatterns ${setdenoms[setname].join(' ')}" : ''} \
    ${quant && normalize ? "--median-normalize" : ''}
    ${quant && normalize ? "sed 's/^/$setname'\$'\t/' < normalization_factors_psms > $normfactors" : ''}
  """
}


/*
* Step 4: Infer and quantify proteins and genes
*/

// Group set T-D combinations and remove those with only target or only decoy
pre_tprepgs_in = Channel.create()
dprepgs_in = Channel.create()
prepgs_in
  .groupTuple(by: 0) // group by setname/acctype
  .filter { it -> it[1].size() == 2 } // must have target and decoy ?
  .transpose()
  .choice(pre_tprepgs_in, dprepgs_in) { it[1] == 'target' ? 0 : 1 }
// combine target with fasta files
pre_tprepgs_in
  .combine(fdrdbs)
  .set { tprepgs_in }

process proteinGeneSymbolTableFDR {
  
  when: !params.onlypeptides
  input:
  set val(setname), val(td), file('tpsms'), file('tpeptides'), file(tfasta), file(dfasta) from tprepgs_in
  set val(setname), val(td), file('dpsms'), file('dpeptides') from dprepgs_in
  each acctype from acctypes

  output:
  set val(setname), val(acctype), file("${setname}_protfdr") into protfdrout
  file('warnings') optional true into fdrwarnings
  set val(setname), val(acctype), path(normfactors) optional true into protnormfac

  script:
  scorecolpat = acctype == 'proteins' ? '^q-value$' : 'linear model'
  denom = !params.noquant && setdenoms ? setdenoms[setname] : false
  specialdenom = denom && (denom[0] == 'sweep' || denom[0] == 'intensity')
  normfactors = "${setname}_normfacs"
  quant = !params.noquant && (!params.noms1quant || params.isobaric)
  """
  # score col is linearmodel_qval or q-value, but if the column only contains 0.0 or NA (no linear modeling possible due to only q<10e-04), we use svm instead
  tscol=\$(head -1 tpeptides| tr '\\t' '\\n' | grep -n "${scorecolpat}" | cut -f 1 -d':')
  dscol=\$(head -1 dpeptides| tr '\\t' '\\n' | grep -n "${scorecolpat}" | cut -f 1 -d':')
  if [ -n "\$(cut -f \$tscol tpeptides| tail -n+2 | egrep -v '(NA\$|0\\.0\$)')" ] && [ -n "\$(cut -f \$dscol dpeptides| tail -n+2 | egrep -v '(NA\$|0\\.0\$)')" ]
    then
      scpat="${scorecolpat}"
      logflag="--logscore"
    else
      scpat="svm"
      logflag=""
      echo 'Not enough q-values or linear-model q-values for peptides to calculate FDR for ${acctype} of set ${setname}, using svm score instead.' >> warnings
  fi
  msstitch ${acctype} -i tpeptides --decoyfn dpeptides -o "${setname}_protfdr" --scorecolpattern "\$scpat" \$logflag \
    ${acctype != 'proteins' ? "--targetfasta '$tfasta' --decoyfasta '$dfasta' ${params.fastadelim ? "--fastadelim '${params.fastadelim}' --genefield '${params.genefield}'": ''}" : ''} \
    ${!params.noquant ? "${!params.noms1quant ? '--ms1quant' : ''} ${setisobaric && setisobaric[setname] ? '--isobquantcolpattern plex --minint 0.1' : ''}" : ''} \
    ${quant ? '--psmtable tpsms' : ''} \
    ${quant && setisobaric && setisobaric[setname] && params.keepnapsmsquant ? '--keep-psms-na-quant' : ''} \
    ${denom && denom[0] == 'sweep' ? '--mediansweep --logisoquant' : ''} \
    ${denom && denom[0] == 'intensity' ? '--medianintensity' : ''} \
    ${denom && !specialdenom ? "--denompatterns ${setdenoms[setname].join(' ')} --logisoquant" : ''} \
    ${normalize ? "--median-normalize" : ''}
    ${normalize ? "sed 's/^/$setname'\$'\t/' < normalization_factors_tpsms > $normfactors" : ''}
  """
}
    

psmwarnings
  .concat(pepwarnings)
  .concat(fdrwarnings)
  .toList()
  .set { warnings }

protgenes = (normalize ? protfdrout.join(protnormfac, by:[0, 1]) : protfdrout )

peptides_out
  .filter { it[2] == 'target' }
  // setname, acctype, outfile
  .map { it -> [it[0], it[1], it[3]] }
  .set { tpeps }

peps_tomerge = (normalize ? tpeps.join(pepnormfac) : tpeps)

peps_tomerge
  .concat(protgenes)
  .set { features_out }

features_out
  .groupTuple(by: 1)  // all outputs of same accession type together.
  .set { ptables_to_merge }

psmlookup
  .filter { it[0] == 'target' }
  .collect()
  .map { it[1] }
  .set { tlookup }

/*
* Step 5: Create reports
*/

process proteinPeptideSetMerge {

  input:
  set val(setnames), val(acctype), file(tables), file(normfacs) from ptables_to_merge
  file(lookup) from tlookup
  file('sampletable') from Channel.from(sampletable).first()
  
  output:
  set val(acctype), file('proteintable'), file('sampletable') into featqc_extra_peptide_samples
  set val(acctype), file('proteintable'), file(normfacs) into merged_feats

  script:
  """
  # SQLite lookup needs copying to not modify the input file which would mess up a rerun with -resume
  cat $lookup > db.sqlite
  msstitch merge -i ${tables.join(' ')} --setnames ${setnames.join(' ')} --dbfile db.sqlite -o mergedtable \
    --fdrcolpattern '^q-value\$' ${acctype != 'peptides' ? '--mergecutoff 0.01' : ''} \
    ${!params.noquant && !params.noms1quant ? "--ms1quantcolpattern area" : ''} \
    ${!params.noquant && setisobaric ? "--isobquantcolpattern plex" : ''} \
    ${params.onlypeptides ? "--no-group-annotation" : ''}
   
  # make a header for sample names, first clean it from #-sign and fix name
  head -n1 mergedtable | sed 's/\\#/Amount/g;s/\\ \\-\\ Amount\\ fully\\ quanted\\ PSMs/_fully_quanted_psm_count/g' > header
  # exchange sample names on isobaric fields in header
  ${params.sampletable ? 'sed "s/[^A-Za-z0-9_\\t]/_/g" sampletable > clean_sampletable' : ''}
  ${params.sampletable && setisobaric ?  
    'while read line ; do read -a arr <<< $line ; sed -i "s/${arr[0]}_\\([a-z0-9]*plex\\)_${arr[1]}/${arr[4]}_${arr[3]}_${arr[2]}_\\1_${arr[1]}/" header ; done < <(paste <(cut -f2 sampletable) clean_sampletable) > rawset_cleansampletable' \
  :  ''}
  cat header <(tail -n+2 mergedtable) > feats
  ${params.deqms ? "numfields=\$(head -n1 feats | tr '\t' '\n' | wc -l) && deqms.R && paste <(head -n1 feats) <(head -n1 deqms_output | cut -f \$(( numfields+1 ))-\$(head -n1 deqms_output|wc -w)) > tmpheader && cat tmpheader <(tail -n+2 deqms_output) > proteintable" : 'mv feats proteintable'}
  """
}


psm_result
  .filter { it[0] == 'target' }
  .merge(scans_result)
  .map { it -> [it[0], it[1], it[2], it[3].unique()] }
  .set { targetpsm_result }


process psmQC {
  input:
  set val(td), file('psms'), file('scans'), val(plates) from targetpsm_result
  val(setnames) from setnames_psmqc
  output:
  set val('psms'), file('psmqc.html'), file('summary.txt') into psmqccollect
  val(plates) into qcplates
  // TODO no proteins == no coverage for pep centric
  script:
  """
  qc_psms.R ${setnames[0].size()} ${fractionation ? 'TRUE' : 'FALSE'} ${plates.join(' ')}
  echo "<html><body>" > psmqc.html
  for graph in psm-scans missing-tmt miscleav
    do
    [[ -e \$graph ]] && echo "<div class=\\"chunk\\" id=\\"\${graph}\\"> \$(sed "s/id=\\"/id=\\"\${graph}/g;s/\\#/\\#\${graph}/g" <\$graph) </div>" >> psmqc.html
    done 
  for graph in retentiontime precerror fwhm fryield msgfscore
    do
    for plateid in ${plates.join(' ')}
      do
      plate="PLATE___\${plateid}___\${graph}"
    [[ -e \$plate ]] && echo "<div class=\\"chunk \$plateid\\" id=\\"\${graph}\\"> \$(sed "s/id=\\"/id=\\"\${plate}/g;s/\\#/\\#\${plate}/g" < \$plate) </div>" >> psmqc.html
      done 
    done
  echo "</body></html>" >> psmqc.html
  """
}

featqc_extra_peptide_samples
  .filter { it[0] == 'peptides' }
  .map { it -> [it[1], it[2]] }
  .set { featqc_peptides_samples }

merged_feats
  .combine(featqc_peptides_samples)
  .set { featqcinput }


process featQC {
  publishDir "${params.outdir}", mode: 'copy', overwrite: true, saveAs: {it == "feats" ? "${acctype}_table.txt": null}

  input:
  set val(acctype), file('feats'), file(normfacs), file(peptable), file(sampletable) from featqcinput
  val(setnames) from setnames_featqc

  output:
  file('feats') into featsout
  set val(acctype), file('featqc.html'), file('summary.txt'), file('overlap') into qccollect

  script:
  show_normfactors = setdenoms && normalize && !setdenoms.values().flatten().any { it == 'sweep' }
  """
  # combine multi-set normalization factors
  cat ${normfacs} > allnormfacs
  # Create QC plots and put them base64 into HTML, R also creates summary.txt
  # FIXME normalization factor plots should not depend on denoms, can also be sweep when deqms has support for that
  # ... change switch to that here and below: normalize ? --normtable ... 
  qc_protein.R --sets ${setnames.collect() { "'$it'" }.join(' ')} --feattype ${acctype} --peptable $peptable ${params.sampletable ? "--sampletable $sampletable" : ''} ${show_normfactors ? '--normtable allnormfacs' : ''}
  echo "<html><body>" > featqc.html
  for graph in featyield precursorarea ${show_normfactors ? 'normfactors': ''} nrpsms nrpsmsoverlapping percentage_onepsm ms1nrpeps;
    do
    [ -e \$graph ] && echo "<div class=\\"chunk\\" id=\\"\${graph}\\"> \$(sed "s/id=\\"/id=\\"${acctype}-\${graph}/g;s/\\#/\\#${acctype}-\${graph}/g" <\$graph) </div>" >> featqc.html
    done 
    # coverage and isobaric plots are png because a lot of points
    [ -e isobaric ] && paste -d \\\\0  <(echo "<div class=\\"chunk\\" id=\\"isobaric\\"><img src=\\"data:image/png;base64,") <(base64 -w 0 isobaric) <(echo '"></div>') >> featqc.html
    [ -e coverage ] && paste -d \\\\0  <(echo "<div class=\\"chunk\\" id=\\"coverage\\"><img src=\\"data:image/png;base64,") <(base64 -w 0 coverage) <(echo '"></div>') >> featqc.html
  # Fetch special (multi-pane) DEqMS and PCA plots
  # Use ls to check because wildcard doesnt work in -e
  ls deqms_volcano_* && echo '<div class="chunk" id="deqms">' >> featqc.html
  for graph in deqms_volcano_*;
    do
    paste -d \\\\0  <(echo '<div><img src="data:image/png;base64,') <(base64 -w 0 \$graph) <(echo '"></div>') >> featqc.html
    done
  ls deqms_volcano_* && echo '</div>' >> featqc.html
  [ -e pca ] && echo '<div class="chunk" id="pca">' >> featqc.html && for graph in pca scree;
    do 
    echo "<div> \$(sed "s/id=\\"/id=\\"${acctype}-\${graph}/g;s/\\#/\\#${acctype}-\${graph}/g" <\$graph) </div>" >> featqc.html
    done
    [ -e pca ] && echo '</div>' >> featqc.html

  echo "</body></html>" >> featqc.html
  ${acctype == 'peptides' ? 'touch summary.txt' : ''}

  # Create overlap table
  qcols=\$(head -n1 feats |tr '\\t' '\\n'|grep -n "_q-value"| tee nrsets | cut -f 1 -d ':' |tr '\\n' ',' | sed 's/\\,\$//')
  protcol=\$(head -n1 feats | tr '\\t' '\\n' | grep -n Protein | cut -f1 -d ':')
  ${acctype == 'peptides' ? 'cut -f1,"\$qcols","\$protcol" feats | grep -v ";" > tmpqvals' : 'cut -f1,"\$qcols" feats > qvals'}
  ${acctype == 'peptides' ? 'nonprotcol=\$(head -n1 tmpqvals | tr "\\t" "\\n" |grep -vn Protein | cut -f1 -d":" | tr "\\n" "," | sed "s/\\,\$//") && cut -f"\$nonprotcol" tmpqvals > qvals' : ''}
  nrsets=\$(wc -l nrsets | sed 's/\\ .*//')
  # read lines, sed removes all non-A chars so only N from NA is left.
  while read line ; do 
  	nr=\$(printf "\$line" |wc -m)  # Count NA
  	overlap=\$(( \$nrsets-\$nr )) # nrsets minus NAcount is the overlap
  	echo "\$overlap" >> setcount
  done < <(tail -n+2 qvals | cut -f2- | sed 's/[^A]//g' )
  echo nr_sets\$'\t'nr_${acctype} > overlap
  for num in \$(seq 1 \$nrsets); do 
  	echo "\$num"\$'\t'\$( grep ^"\$num"\$ setcount | wc -l) >> overlap
  done
  """
}

qccollect
  .concat(psmqccollect)
  .toList()
  .map { it -> [it.collect() { it[0] }, it.collect() { it[1] }, it.collect() { it[2] }, it.collect() { it[3] }] }
  .set { collected_feats_qc }


process collectQC {

  publishDir "${params.outdir}", mode: 'copy', overwrite: true

  input:
  set val(acctypes), file('feat?'), file('summary?'), file('overlap?') from collected_feats_qc
  val(plates) from qcplates
  file('sw_ver') from software_versions_qc
  file('warnings??') from warnings

  output:
  set file('qc_light.html'), file('qc_full.html')

  script:
  """
  count=1; for ac in ${acctypes.join(' ')}; do mv feat\$count \$ac.html; mv summary\$count \${ac}_summary; mv overlap\$count \${ac}_overlap; ((count++)); done
  join -j 1 -o auto -t '\t' <(head -n1 psms_summary) <(head -n1 peptides_summary) > psmpepsum_header
  join -j 1 -o auto -t '\t' <(tail -n+2 psms_summary | sort -k1b,1 ) <(tail -n+2 peptides_summary | sort -k1b,1 ) > psmpepsum_tab

  # onlypeptides makes a quick summary, else also add proteins
  ${params.onlypeptides ? 'cat psmpepsum_header psmpepsum_tab | tee summary pre_summary_light_tab' : 'join -j 1 -o auto -t \'\t\' psmpepsum_tab <(sort -k1b,1 <(tail -n+2 proteins_summary)) > pepprotsum_tab && join -j 1 -o auto -t \'\t\' psmpepsum_header <(head -n1 proteins_summary) > pepprotsum_head'}
  ${params.onlypeptides ? "awk -v FS='\\t' -v OFS='\\t' '{print \$1,\$3,\$2}' pre_summary_light_tab > summary_light" : ""}

  # in case of genes, join those on the prot/pep tables (full summary) and psmpeptables (light summary), else passthrough those to summaries
  ${params.genes ?  'join -j 1 -o auto -t \'\t\' pepprotsum_tab <( sort -k1b,1 <( tail -n+2 genes_summary)) > summary_tab && join -j 1 -o auto -t \'\t\' pepprotsum_head <(head -n1 genes_summary) > summary_head && cat summary_head summary_tab > summary' : "${!params.onlypeptides ? 'cat pepprotsum_head pepprotsum_tab | tee summary summary_light' : ""}"}
  ${params.genes ?  'join -j 1 -o auto -t \'\t\' psmpepsum_tab <( sort -k1b,1 <(tail -n+2 genes_summary)) > summary_light_tab' : ''}
  ${params.genes ?  'join -j 1 -o auto -t \'\t\' psmpepsum_header <( head -n1 genes_summary) > summary_light_head && cat summary_light_head summary_light_tab > summary_light' : ''}

  # remove Yaml from software_versions to get HTML
  grep -A \$(wc -l sw_ver | cut -f 1 -d ' ') "data\\:" sw_ver | tail -n+2 > sw_ver_cut
  
  # merge warnings
  ls warnings* && cat warnings* > warnings.txt
  # collect and generate HTML report
  qc_collect.py $baseDir/assets/qc_full.html $params.name ${fractionation ? "frac" : "nofrac"} ${plates.join(' ')}
  qc_collect.py $baseDir/assets/qc_light.html $params.name ${fractionation ? "frac" : "nofrac"} ${plates.join(' ')}
  """
}


/* 
 * STEP 3 - Output Description HTML
*/
process output_documentation {
    tag "$prefix"

    publishDir "${params.outdir}/Documentation", mode: 'copy'

    input:
    file output_docs

    output:
    file "results_description.html"

    script:
    """
    markdown_to_html.r $output_docs results_description.html
    """
}



/*
 * Completion e-mail notification
 */
workflow.onComplete {

    // Set up the e-mail variables
    def subject = "[lehtiolab/ddamsproteomics] Successful: $workflow.runName"
    if(!workflow.success){
      subject = "[lehtiolab/ddamsproteomics] FAILED: $workflow.runName"
    }
    def email_fields = [:]
    email_fields['version'] = workflow.manifest.version
    email_fields['runName'] = custom_runName ?: workflow.runName
    email_fields['success'] = workflow.success
    email_fields['dateComplete'] = workflow.complete
    email_fields['duration'] = workflow.duration
    email_fields['exitStatus'] = workflow.exitStatus
    email_fields['errorMessage'] = (workflow.errorMessage ?: 'None')
    email_fields['errorReport'] = (workflow.errorReport ?: 'None')
    email_fields['commandLine'] = workflow.commandLine
    email_fields['projectDir'] = workflow.projectDir
    email_fields['summary'] = summary
    email_fields['summary']['Date Started'] = workflow.start
    email_fields['summary']['Date Completed'] = workflow.complete
    email_fields['summary']['Pipeline script file path'] = workflow.scriptFile
    email_fields['summary']['Pipeline script hash ID'] = workflow.scriptId
    if(workflow.repository) email_fields['summary']['Pipeline repository Git URL'] = workflow.repository
    if(workflow.commitId) email_fields['summary']['Pipeline repository Git Commit'] = workflow.commitId
    if(workflow.revision) email_fields['summary']['Pipeline Git branch/tag'] = workflow.revision
    email_fields['summary']['Nextflow Version'] = workflow.nextflow.version
    email_fields['summary']['Nextflow Build'] = workflow.nextflow.build
    email_fields['summary']['Nextflow Compile Timestamp'] = workflow.nextflow.timestamp

    // Render the TXT template
    def engine = new groovy.text.GStringTemplateEngine()
    def tf = new File("$baseDir/assets/email_template.txt")
    def txt_template = engine.createTemplate(tf).make(email_fields)
    def email_txt = txt_template.toString()

    // Render the HTML template
    def hf = new File("$baseDir/assets/email_template.html")
    def html_template = engine.createTemplate(hf).make(email_fields)
    def email_html = html_template.toString()

    // Render the sendmail template
    def smail_fields = [ email: params.email, subject: subject, email_txt: email_txt, email_html: email_html, baseDir: "$baseDir" ]
    def sf = new File("$baseDir/assets/sendmail_template.txt")
    def sendmail_template = engine.createTemplate(sf).make(smail_fields)
    def sendmail_html = sendmail_template.toString()

    // Send the HTML e-mail
    if (params.email) {
        try {
          if( params.plaintext_email ){ throw GroovyException('Send plaintext e-mail, not HTML') }
          // Try to send HTML e-mail using sendmail
          [ 'sendmail', '-t' ].execute() << sendmail_html
          log.info "[lehtiolab/ddamsproteomics] Sent summary e-mail to $params.email (sendmail)"
        } catch (all) {
          // Catch failures and try with plaintext
          [ 'mail', '-s', subject, params.email ].execute() << email_txt
          log.info "[lehtiolab/ddamsproteomics] Sent summary e-mail to $params.email (mail)"
        }
    }

    // Write summary e-mail HTML to a file
    def output_d = new File( "${params.outdir}/Documentation/" )
    if( !output_d.exists() ) {
      output_d.mkdirs()
    }
    def output_hf = new File( output_d, "pipeline_report.html" )
    output_hf.withWriter { w -> w << email_html }
    def output_tf = new File( output_d, "pipeline_report.txt" )
    output_tf.withWriter { w -> w << email_txt }

    log.info "[lehtiolab/ddamsproteomics] Pipeline Complete"

}
