=head1 LICENSE

Copyright [1999-2014] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute

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

package EnsEMBL::Web::TmpFile::VcfTabix;

## EnsEMBL::Web::TmpFile::VcfTabix - module for dealing with tabix indexed VCF
## files generated by the VEP

use strict;
use Compress::Zlib qw(gzopen $gzerrno);

use parent 'EnsEMBL::Web::TmpFile::ToolsOutput';

our $species_defs = EnsEMBL::Web::SpeciesDefs->new;

sub compress { return 1; }

sub content {
  my $self = shift;
  my %args = @_;
  
  my $file = $self->{full_path};
  
  # normal
  if(!%args) {
    return $self->SUPER::content();
  }
  
  # get args
  my $from = $args{from} || 0;
  my $to   = $args{to}   || 1e12;
  my $loc  = $args{location};
  my $fh_string;
  
  if(defined($loc) && $loc =~ /\w+/) {
    $fh_string = "tabix -h $file $loc | ";
  }
  else {
    $fh_string = "zcat -q $file | ";
  }
  
  # get script path and perl binary
  my $script = $species_defs->ENSEMBL_VEP_FILTER_SCRIPT or die "ERROR: No filter_vep.pl script defined (ENSEMBL_VEP_FILTER_SCRIPT)\n";
     $script = join '/', $species_defs->ENSEMBL_SERVERROOT, $script;
  my $perl   = join ' ', 'perl', map { $_ =~ /^\// && -e $_ ? ('-I', $_) : () } reverse @INC;
  my $opts   = $species_defs->ENSEMBL_VEP_FILTER_SCRIPT_OPTIONS || {};
     $opts   = join ' ', map { defined $opts->{$_} ? "$_ $opts->{$_}" : () } keys %$opts;
   
  if($args{filter}) {
    $fh_string .= sprintf("%s %s %s -filter '%s' -ontology -only_matched -start %i -limit %i 2>&1 | ", $perl, $script, $opts, $args{filter}, $from, ($to - $from) + 1);
  }
  
  #print STDERR "$fh_string\n";
  
  my ($content, $line_number);
  
  my $first_line = 1;
  open IN, $fh_string;
  while(<IN>) {
    if($first_line) {
      die "$_\n" unless $_ =~ /^\#/;
      $first_line = 0;
    }
    
    # filter_vep.pl takes care of limiting
    if($args{filter}) {
      $content .= $_;
    }
    
    # no filters, we have to do the limiting here
    else {
      $line_number++ unless /^\#/;
      $content .= $_ if /^\#/ || ($line_number >= $from && $line_number <= $to);
      last if $line_number > $to;
    }
  }
  close IN;
  
  # convert format?
  if(defined($args{format}) && $args{format} ne 'vcf') {
    my $method = 'convert_to_'.$args{format};
    
    return $self->can($method) ? $self->$method($content) : $content;
  }
  
  else {
    return $content;
  }
}

sub convert_to_txt {
  my $self = shift;
  my $content = shift;
  
  my ($headers, $rows) = @{$self->parse_content($content)};
  
  my $return = '#'.join("\t", map {s/^ID$/Uploaded_variation/; $_} @$headers)."\n";
  foreach my $row(@$rows) {
    $row->{Uploaded_variation} ||= $row->{ID} if $row->{ID};
    $return .= join("\t", map {(defined($row->{$_}) && $row->{$_} ne '') ? $row->{$_} : '-'} @$headers);
    $return .= "\n";
  }
  
  return $return;
}

sub convert_to_vep {
  my $self = shift;
  my $content = shift;
  
  my ($headers, $rows) = @{$self->parse_content($content)};
  
  # find Existing_variation field
  # this is the last one we want to print as a separate field
  my $i = 0;
  
  foreach(@{$headers}) {
    last if $_ eq 'Existing_variation';
    $i++;
  }
  
  # add headers
  my $return = '#'.join("\t", map {s/^ID$/Uploaded_variation/; $_} @{$headers}[0..$i])."\tExtra\n";
  
  foreach my $row(@$rows) {
    my $first = 1;
    $row->{Uploaded_variation} ||= $row->{ID} if $row->{ID};
    
    for my $j(0..$#{$headers}) {
      
      # get header and value
      my ($h, $v) = ($headers->[$j], $row->{$headers->[$j]});
      
      # normal column
      if($j <= $i) {
        $return .= $j ? "\t" : '';
        $return .= (defined($v) && $v ne '') ? $v : '-';
      }
      
      # extra column
      elsif(defined($v) && $v ne '') {
        if($first) {
          $return .= "\t";
          $first = 0;
        }
        else {
          $return .= ";";
        }
        
        $return .= $h.'='.$v;
      }
    }
    
    $return .= "\n";
  }
  
  return $return;
}

sub parse_content {
  my $self = shift;
  my $content = shift;
  
  my ($line_count, @headers, @rows, @csq_headers, @combined_headers);
  
  # define some fields we don't want
  my %exclude_fields = (
    CHROM => 1,
    POS => 1,
    REF => 1,
    ALT => 1,
    INFO => 1,
    QUAL => 1,
    FILTER => 1,
  );
  
  for(split /\n/, $content) {
    
    # header
    if(m/^##/ && /INFO\=\<ID\=CSQ/) {
      m/Format\: (.+?)\"/;
      @csq_headers = split '\|', $1;
    }
    elsif(s/^#//) {
      @headers = split /\s+/;
      
      # we don't want anything after the INFO field (index pos 8)
      for my $i(8..$#headers) {
        $exclude_fields{$headers[$i]} = 1;
      }
      
      @combined_headers = grep {!defined($exclude_fields{$_})} (@headers, @csq_headers);
      splice(@combined_headers, 1, 0, 'Location');
    }
    
    # data
    elsif(!/^#/) {
      $line_count++;
      
      my @split = split /\s+/;
      my %raw_data = map {$headers[$_] => $split[$_]} 0..$#split;
     
      if($raw_data{CHROM} !~ /^chr_/i) { 
        $raw_data{CHROM} =~ s/^chr(om)?(osome)?//i;
      }
      
      # special case location col
      my ($start, $end) = ($raw_data{POS}, $raw_data{POS});
      my ($ref, $alt) = ($raw_data{REF}, $raw_data{ALT});
      $end += (length($ref) - 1);
      
      my %tmp = map {$_ => 1} ($start, $end);
      $raw_data{Location} = sprintf("%s:%s", $raw_data{CHROM}, join("-", sort {$a <=> $b} keys %tmp));
      
      if(length($ref) != length($alt)) {
        $ref = substr($ref, 1);
        $alt = substr($alt, 1);
        
        $ref ||= '-';
        $alt ||= '-';
      }
      
      # make ID
      $raw_data{ID} ||= $raw_data{CHROM}.'_'.$start.'_'.$ref.'/'.$alt;
      
      while(m/CSQ\=(.+?)(\;|$|\s)/g) {
        foreach my $csq(split '\,', $1) {
          $csq =~ s/\&/\,/g;
          my @csq_split = split '\|', $csq;
          
          my %data = %raw_data;
          $data{$csq_headers[$_]} = $csq_split[$_] for 0..$#csq_split;
          
          delete $data{$_} for keys %exclude_fields;
          
          push @rows, \%data;
        }
      }
    }
  }
  
  return [\@combined_headers, \@rows, $line_count];
}

1;
