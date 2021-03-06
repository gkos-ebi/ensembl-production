=head1 LICENSE

Copyright [1999-2013] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

=pod


=head1 CONTACT

  Please email comments or questions to the public Ensembl
  developers list at <dev@ensembl.org>.

  Questions may also be sent to the Ensembl help desk at
  <helpdesk@ensembl.org>.

=head1 NAME

Bio::EnsEMBL::Production::Pipeline::FASTA::ConcatFiles

=head1 DESCRIPTION

Performs a find in the DNA dumps directory for the given species and then
concats files which match a specified name pattern. We only allow
two types of concats; DNA and RM DNA. The concat file is a series
of cat command calls from all other Gzipped FASTA dumps (allowed under
the GZip specification). 

Allowed parameters are:

=over 8

=item release - Needed to build the target path

=item species - Required to indicate which species we are working with

=item data_type - The type of data to work with. Can be I<dna>, I<dn_sm> or I<dna_rm>

=item base_path - The base of the dumps

=back

=cut

package Bio::EnsEMBL::Production::Pipeline::FASTA::ConcatFiles;

use strict;
use warnings;
use base qw/Bio::EnsEMBL::Production::Pipeline::FASTA::Base/;

use File::Spec;
use File::stat;

sub file_pattern {
  my ($self,$type) = @_;
   my %regexes = (
    dna => qr/.+\.dna\..+\.fa\.gz$/,
    dna_rm => qr/.+\.dna_rm\..+\.fa\.gz$/,
    dna_sm => qr/.+\.dna_sm\..+\.fa\.gz$/,
  );
  return $regexes{$type};
}

sub fetch_input {
  my ($self) = @_;
  foreach my $key (qw/data_type species release base_path/) {
    $self->throw("Cannot find the required parameter $key") unless $self->param($key);
  }
  return;
}

# sticks ends of files together into one big file.
sub run {
  my ($self) = @_;
  
  my @file_list = @{$self->get_dna_files()};
  my $count = scalar(@file_list);
  my $running_total_size = 0;
  
  if($count) {
    my $target_file = $self->target_file();
    $self->info("Concatting type %s with %d file(s) into %s", $self->param('data_type'), $count, $target_file);
    
    if(-f $target_file) {
      $self->info("Target already exists. Removing");
      unlink $target_file or $self->throw("Could not remove $target_file: $!");
    }
    
    $self->info('Running concat');
    foreach my $file (@file_list) {
      $self->fine('Processing %s', $file);
      $running_total_size += stat($file)->size;
      system("cat $file >> $target_file") 
        and $self->throw( sprintf('Cannot concat %s into %s. RC %d', $file, $target_file, ($?>>8)));
    }

    $self->info("Catted files together");
    
    my $catted_size = stat($target_file)->size;
    
    if($running_total_size != $catted_size) {
      $self->throw(sprintf('The total size of the files catted together should be %d but was in fact %d. Failing as we expect the catted size to be the same', $running_total_size, $catted_size));
    }
    
    $self->param('target_file', $target_file);
  }
  else {
    $self->throw("Cannot continue as we found no files to concat");
  }
  return;
}

sub write_output {
  my ($self) = @_;
  my $file = $self->param('target_file');
  if($file) {
    $self->dataflow_output_id({ file => $file, species => $self->param('species') }, 1);
  }
  return;
}

sub get_dna_files {
  my ($self) = @_;
  my $path = $self->fasta_path('dna');
  my $data_type = $self->param('data_type'); 
  
  my $regex = $self->file_pattern($data_type);
  my $filter = sub {
    my ($filename) = @_;
    return ($filename =~ $regex && $filename !~ /\.toplevel\./) ? 1 : 0;
  };
  my $files = $self->find_files($path, $filter);
  return [ sort @{$files} ];
}


sub target_file {
  my ($self) = @_;
  # File name format looks like:
  # <species>.<assembly>.<release>.<sequence type>.<id type>.<id>.fa.gz
  # e.g. Homo_sapiens.GRCh37.64.dna_rm.toplevel.fa.gz
  my @name_bits;
  push @name_bits, $self->web_name();
  push @name_bits, $self->assembly();
  push @name_bits, $self->param('release');
  push @name_bits, $self->param('data_type');
  push @name_bits, 'toplevel';
  push @name_bits, 'fa', 'gz';
  my $file_name = join( '.', @name_bits );
  my $dir = $self->fasta_path('dna');
  return File::Spec->catfile( $dir, $file_name );
}

1;
