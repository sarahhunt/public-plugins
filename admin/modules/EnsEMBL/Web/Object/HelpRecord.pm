package EnsEMBL::Web::Object::HelpRecord;

use strict;

use base qw(EnsEMBL::Web::Object::DbFrontend);

sub record_type {
  ## Gets the type of the record(s) requested for i.e. - glossary, view, movie, faq
  my $self = shift;

  my $type = lc $self->hub->function;
  return $type && grep({$type eq $_} qw(glossary view movie faq)) ? $type : undef;
}

sub fetch_for_display {
  my $self   = shift;
  return $self->SUPER::fetch_for_display(@_) if $self->hub->param('id');

  my $type   = $self->record_type;
  $self->SUPER::fetch_for_display({'query' => ['type' => $type]}) if $type;

  my $rose_objects  = $self->rose_objects;
  my $order_by_1    = {qw(glossary word view ensembl_object movie title faq category)}->{$type};
  my $order_by_2    = {qw(view ensembl_action faq question)}->{$type} || 0;

  $self->rose_objects([ sort { ($a->virtual_column_value($order_by_1) cmp $b->virtual_column_value($order_by_1)) || $order_by_2 && ($a->virtual_column_value($order_by_2) cmp $b->virtual_column_value($order_by_2))} @$rose_objects ]) if $rose_objects;
}

sub fetch_for_list {
  return shift->fetch_for_display(@_);
}

sub get_count {
  ## @overrides
  my $self = shift;
  my $type = $self->record_type;
  return 0 unless $type;
  return $self->SUPER::get_count({'query' => ['type' => $type]});
}

### ### ### ### ### ### ### ### ###
### Inherited method overriding ###
### ### ### ### ### ### ### ### ###

sub manager_class {
  ## @overrides
  return shift->rose_manager('HelpRecord');
}

sub show_fields {
  ## @overrides
  my $self = shift;
  my $type = $self->rose_object ? $self->rose_object->type : $self->record_type;
  my @datamap;

  if ($type eq 'glossary') {
    @datamap = (
      'word'           => {'label' => 'Word',            'type' => 'string'  },
      'expanded'       => {'label' => 'Expanded',        'type' => 'text',     'cols' => 60, 'rows' => 5},
      'meaning'        => {'label' => 'Meaning',         'type' => 'html',     'cols' => 60, 'rows' => 5,   'class' => '_tinymce'}
    );
  }
  elsif ($type eq 'view') {
    @datamap = (
      'help_links'          => {'label' => 'Linked URLs',     'type' => 'checklist', 'multiple' => 1},
      'content'        => {'label' => 'Content',         'type' => 'html',     'cols' => 60, 'rows' => 40,  'class' => '_tinymce _tinymce_h_600'}
    );
  }
  elsif ($type eq 'movie') {
    @datamap = (
      'title'          => {'label' => 'Title',           'type' => 'string'  },
      'youtube_id'     => {'label' => 'Youtube ID',      'type' => 'string'  },
      'list_position'  => {'label' => 'List position',   'type' => 'int'     },
      'length'         => {'label' => 'Length',          'type' => 'string'  }
    );
  }
  elsif ($type eq 'faq') {
    @datamap = (
      'category'       => {'label' => 'Category',        'type' => 'dropdown', 'values' => [
        {'value' => 'archives',       'caption' => 'Archives'                     },
        {'value' => 'genes',          'caption' => 'Genes'                        },
        {'value' => 'assemblies',     'caption' => 'Genome assemblies'            },
        {'value' => 'comparative',    'caption' => 'Comparative genomics'         },
        {'value' => 'regulation',     'caption' => 'Regulation'                   },
        {'value' => 'variation',      'caption' => 'Variation'                    },
        {'value' => 'data',           'caption' => 'Export, uploads and downloads'},
        {'value' => 'z_data',         'caption' => 'Other data'                   },
        {'value' => 'core_api',       'caption' => 'Core API'                     },
        {'value' => 'compara_api',    'caption' => 'Compara API'                  },
        {'value' => 'variation_api',  'caption' => 'Variation API'                },
        {'value' => 'regulation_api', 'caption' => 'Regulation API'               }
      ]},
      'question'       => {'label' => 'Question',        'type' => 'html',     'cols' => 80,  'class' => '_tinymce'},
      'answer'         => {'label' => 'Answer',          'type' => 'html',     'cols' => 80,  'class' => '_tinymce'}
    );
  }

  return [
    @datamap,
    'keyword'               => {'label' => 'Keyword',         'type' => 'text',     'cols' => 60},
    'status'                => {'label' => 'Status',          'type' => 'dropdown'},
  ];
}

sub show_columns {
  ## @overrides
  my $self = shift;
  my $type = $self->rose_object ? $self->rose_object->type : $self->record_type;
  my @datamap;

  if ($type eq 'glossary') {
    @datamap = (
      'word'           => {'title' => 'Word'},
      'expanded'       => {'title' => 'Expanded'},
    );
  }
  elsif ($type eq 'view') {
    @datamap = (
      'help_links'          => {'title' => 'Help Links'}
    );
  }
  elsif ($type eq 'movie') {
    @datamap = (
      'title'          => {'title' => 'Title'},
      'youtube_id'     => {'title' => 'Youtube ID'},
    );
  }
  elsif ($type eq 'faq') {
    @datamap = (
      'category'       => {'title' => 'Category'},
      'question'       => {'title' => 'Question'},
    );
  }

  return [
    @datamap,
    'keyword'               => {'title' => 'Keyword'},
    'status'                => {'title' => 'Status'},
  ];
}

sub record_name {
  my $type  = shift->record_type;
  return [ map {'singular' => "$_", 'plural' => "${_}s"}, {'movie' => 'Movie', 'faq' => 'FAQ', 'glossary' => 'Word', 'view' => 'Page view'}->{$type} ]->[0] if $type;
  return {qw(singular Record plural Records)};
}

sub create_empty_object {
  ## @overrides
  ## Adds the type to the empty object before returning it
  my $self = shift;
  my $type = $self->record_type;
  return unless $type; ## TODO - throw exception here
  my $empty_object = $self->SUPER::create_empty_object(@_);
  $empty_object->type($type);
  return $empty_object;
}

sub get_fields {
  ## @overrides
  ## This ignores caching for get_fields method
  my $self = shift;
  delete $self->{'_dbf_show_fields'};
  return $self->SUPER::get_fields(@_);
}

1;