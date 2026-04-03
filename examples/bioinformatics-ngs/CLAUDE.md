# VariantGPT / NGS Pipeline — Project Context
_Example: copy this into your bioinformatics project alongside the base CLAUDE.md_

## Project identity
Clinical genomics variant interpretation pipeline following ACMG/AMP 2015 guidelines.
Processes germline WES/WGS data. Output: clinical variant reports with ACMG classifications.

## Architecture
- **Input**: VCF 4.2 (GRCh38), BAM/CRAM files
- **Annotation**: gnomAD v4.1, ClinVar (monthly), OMIM, SpliceAI, CADD
- **Pipeline**: Nextflow DSL2 on AWS Batch (ap-south-1)
- **Output**: JSON report + PDF clinical summary
- **Classification**: ACMG/AMP 2015 + ClinGen SVI v1.1 updates

## Key file paths
```
data/input/          # Raw VCF files (never paste contents in chat)
data/annotated/      # Annotated VCFs from pipeline
results/             # Classification outputs
pipeline/            # Nextflow workflows
src/                 # Python interpretation scripts
```

## Genomics-specific token hygiene
- Reference VCF variants by HGVS notation only: `NM_007294.4:c.68_69delAG`
- Never paste gnomAD JSON responses — specify fields needed: `AF, nhomalt, popmax_AF`
- Pipeline errors: paste only the `ERROR` and `FATAL` lines, not full stdout
- Use `@data/input/sample.vcf` reference syntax, never paste VCF content
- Cohort size > 100: process in batches, save intermediate to `results/`

## ACMG criteria in use
- PVS1: applied with ClinGen SVI v1.1 thresholds
- PS1/PM5: checked against ClinVar pathogenic variants
- PM2: gnomAD v4.1 AF < 0.0001 (gnomAD non-cancer)
- PP3/BP4: SpliceAI (delta > 0.5 pathogenic) + CADD (PHRED > 25)
- Variant classification: Pathogenic | Likely Pathogenic | VUS | Likely Benign | Benign

## Pipeline stages
1. QC (FastQC, MultiQC)
2. Alignment (BWA-MEM2, GRCh38)
3. Variant calling (GATK HaplotypeCaller / DeepVariant)
4. Annotation (VEP 111, custom plugins)
5. Filtering (custom Python: gnomAD AF, ClinVar, gene panel)
6. ACMG classification (VariantGPT engine)
7. Report generation (PDF + JSON)

## AWS configuration
- Region: ap-south-1 (Mumbai)
- Compute: AWS Batch (Spot instances)
- Storage: S3 (apollo-genomics bucket)
- IAM role: variant-processor (read S3, write results)

## Frozen constraints (never change without team sign-off)
- GRCh38 only (no hg19)
- gnomAD v4.1 (not v3) for AF filter
- CADD PHRED threshold: 25 (not 20)
- Report format: v2.3 (clinical team dependency)

## Clinical compliance
- PHI handling: sample IDs anonymised before processing
- Audit log: all classifications logged with timestamp + analyst
- HIPAA: no patient names/DOB/MRN in any file or log
- Lynch syndrome panel: MLH1, MSH2, MSH6, PMS2 (always report regardless of phenotype)
