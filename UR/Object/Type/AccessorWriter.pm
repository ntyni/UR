
package UR::Object::Type::AccessorWriter;

package UR::Object::Type;

use strict;
use warnings;

sub construct_class_from_data
{
    my $self = shift;

    no strict 'refs';

    my %params = @_;
    my $class_name = $params{"class_name"};
    my @id_properties = @{ $params{id_properties} };
    my @other_properties = @{ $params{other_properties} };
    my @class_properties = ($params{class_properties} ? @{ $params{class_properties} } : ());

    for my $property (@id_properties)
    {
        UR::Object::Type->mk_ro_accessor($class_name,$property,uc($property));
    }

    for my $property (@other_properties)
    {
        UR::Object::Type->mk_rw_accessor($class_name,$property,uc($property));
    }

    for my $property (@class_properties)
    {
        UR::Object::Type->mk_class_accessor($class_name,$property);
    }

    my $props = [@id_properties, @other_properties];
    my $cols = [map { uc($_) } @$props];

    my @isa = @{$class_name . '::ISA'};
    for my $base (@isa) {
        my $isl = ${$base . '::immediate_subclasses_loaded'} ||= [];
        push @$isl, $class_name;
        $isl = ${$base . '::Ghost::immediate_subclasses_loaded'} ||= [];
        push @$isl, $class_name . '::Ghost';
    }

}

sub mk_rw_accessor {
    no warnings;
    my ($self, $class_name, $accessor_name, $column_name, $property_name, $is_transient) = @_;
    $property_name ||= $accessor_name;

    # The accessors may compare undef and an empty
    # string.  For speed, we turn warnings off rather
    # than add extra code to make the warning disappear.
    no warnings;
    no strict 'refs';

    my $accessor = sub {
        if (@_ > 1) {
            my $old = $_[0]->{ $property_name };
            my $new = $_[1];
            if ($old ne $new)
            {
                $_[0]->{ $property_name } = $new;
                $_[0]->signal_change( $accessor_name, $old, $new ) unless $is_transient;
            }
            return $new;
        }
        return $_[0]->{ $property_name };
    };

    no strict 'refs';

    *{$class_name ."::$accessor_name"}  = $accessor;

    #$column_name = uc($column_name);

    if ($column_name)
    {
        *{$class_name ."::" . $column_name} = $accessor;

        # These are for backward-compatability with old modules.  Remove asap.
        ${$class_name . '::column_for_property'}
            {$property_name} = $column_name;

        ${$class_name . '::property_for_column'}
            {$property_name} = $accessor_name;
    }
}

sub mk_ro_accessor {
    no warnings;
    no strict 'refs';
    my ($self, $class_name, $accessor_name, $column_name, $property_name) = @_;
    $property_name ||= $accessor_name;
    my $accessor = sub {
        if (@_ > 1) {
            my $old = $_[0]->{ $property_name};
            my $new = $_[1];
            if ($old ne $new)
            {
                Carp::confess("Cannot change read-only property $accessor_name for class $class_name!"
                . "  Failed to update " . $_[0]->display_name_full . " property: $property_name from $old to $new");
            }
            return $new;
        }
        return $_[0]->{ $property_name };
    };


    *{$class_name ."::$accessor_name"} = $accessor;

    $column_name = uc($column_name);
    
    if ($column_name)
    {
        *{$class_name ."::" . $column_name}  = $accessor;

        # These are for backward-compatability with old modules.  Remove asap.
        ${$class_name . '::column_for_property'}
            {$property_name} = $column_name;

        ${$class_name . '::property_for_column'}
            {$property_name} = $accessor_name;
    }
}

sub mk_id_based_object_accessor {
    no warnings;
    my ($self, $class_name, $accessor_name, $id_by, $r_class_name) = @_;

    # The accessors may compare undef and an empty
    # string.  For speed, we turn warnings off rather
    # than add extra code to make the warning disappear.
    no warnings;
    no strict 'refs';

    unless (ref($id_by)) {
        $id_by = [ $id_by ];
    }

    my $id_resolver;
    my $id_decomposer;
    my @id;
    my $id;
    my $accessor = sub {
        my $self = shift;
        if (@_) {
            my $object_value = shift;
            $id_decomposer ||= $r_class_name->get_class_object->get_composite_id_decomposer;
            @id = ( defined($object_value) ? $id_decomposer->($object_value->id) : () );
            for my $id_property_name (@$id_by) {
                $self->$id_property_name(shift @id);
            }
            return $object_value;
        }
        else {
            $id_resolver ||= $r_class_name->get_class_object->get_composite_id_resolver;
            @id = map { $self->$_ } @$id_by;
            $id = $id_resolver->(@id);
            return if not defined $id;
            return $r_class_name->get($id);
        }
    };

    no strict 'refs';
    *{$class_name ."::$accessor_name"}  = $accessor;
}

sub mk_indirect_ro_accessor {
    my ($self, $class_name, $accessor_name, $via, $to) = @_;

    my $accessor = sub {
        my $self = shift;
        Carp::confess("assignment value passed to read-only indirect accessor $accessor_name for class $class_name!") if @_;
        my @bridges = $self->$via;
        return unless @bridges;
        my @results = map { $_->$to } @bridges;
        $self->context_return(@results); 
    };

    no strict 'refs';
    *{$class_name ."::$accessor_name"}  = $accessor;
}

sub mk_indirect_rw_accessor {
    my ($self, $class_name, $accessor_name, $via, $to) = @_;

    my $accessor = sub {
        my $self = shift;
        my @bridges = $self->$via;
        if (@_) {
            unless (@bridges) {
                Carp::confess("Cannot set $accessor_name on $class_name $self->{id}: property is via $via which is not set!");
            }
            if (@bridges > 1) {
                Carp::confess("Cannot set $accessor_name on $class_name $self->{id}: multiple cases of $via found, via which the property is set!");
            }
            return $bridges[0]->$to(@_);
        }
        return unless @bridges;
        my @results = map { $_->$to } @bridges;
        $self->context_return(@results); 
    };

    no strict 'refs';
    *{$class_name ."::$accessor_name"}  = $accessor;
}


sub mk_calculation_accessor {
    my ($self, $class_name, $accessor_name, $calculation_src, $calculate_from) = @_;

    my $accessor;
    my @src;

    if (not defined $calculation_src or $calculation_src eq '') {
        $accessor = \&{ $class_name . '::' . $accessor_name };
        unless ($accessor) {
            die "$accessor_name not defined in $class_name!  Define it, or specify a calculate => sub{} or calculate => \$perl_src in the class definition.";
        }
    }
    elsif (ref($calculation_src) eq 'CODE') {
        $accessor = sub {
            my $self = shift;
            if (@_) {
                Carp::confess("$class_name $accessor_name is a read-only property derived from @$calculate_from");
            }
            return $calculation_src->(map { $self->$_ } @$calculate_from);        
        };
    }
    elsif ($calculation_src =~ /^[^\:\W]+$/) {
        # built-in formula
        my $module_name = "UR::Object::Type::AccessorWriter::" . ucfirst(lc($calculation_src));
        eval "use $module_name";
        die $@ if $@;
        @src = ( 
            "sub ${class_name}::${accessor_name} {",
            'my $self = $_[0];',
            "${module_name}->calculate(\$self, [" . join(",", map { "'$_'" } @$calculate_from) . "], \@_)",
            '}'
        );
    }
    else {
        @src = ( 
            "sub ${class_name}::${accessor_name} {",
            'my $self = $_[0];',
            (map { "my \$$_ = \$self->$_;" } @$calculate_from),
            $calculation_src,
            '}'
        );
    }

    if ($accessor) {
        no strict 'refs';
        *{$class_name ."::$accessor_name"}  = $accessor;
    }
    elsif (@src) {
        my $src = join("\n",@src);
        eval $src;
        if ($@) {
            die "ERROR IN CALCULATED PROPERTY SOURCE: $class_name $accessor_name\n$@\n";
        }
    }
    else {
        die "Error implementing calcuation accessor for $class_name $accessor_name!";
    }
}

sub mk_dimension_delegate_accessors {
    my ($self, $accessor_name, $ref_class_name, $non_id_properties, $other_accessor_name, $is_transient) = @_;

    # Like mk_rw_accessor, but knows that this accessor is a foreign
    # key to a dimension table, and configures additional accessors.
    # Also makes this accessor "smart", to resolve the dimension
    # id only when needed.

    # Make EAV-like accessors for all of the remote properties
    my $class_name = $self->class_name;
    
    my $other_accessor = sub {
        my $self = shift;
        my $delegate_id = $self->{$accessor_name};
        if (defined($delegate_id)) {
            # We're currently delegating.
            my $delegate = $ref_class_name->get($delegate_id);
            if (not @_) {
                # A simple get.  Delegate.
                return $delegate->$other_accessor_name(@_);
            }
            else {
                # We're setting a value.
                # Switch from delegating to local access.
                # We'll switch back next-time the dimension ID
                # is actually requested by its accessor
                # (farther below).
                my $old = $delegate->$other_accessor_name;
                my $new = shift;                    
                if (do { no warnings; $old ne $new }) {
                    $self->{$accessor_name} = undef;
                    for my $property (@$non_id_properties) {
                        if ($property eq $other_accessor_name) {
                            # set the value locally
                            $self->{$property} = $new;
                        }
                        else {
                            # grab the data from the (now previous) delegate
                            $self->{$property} = $delegate->$property;
                        }
                    }
                    $self->signal_change( $other_accessor_name, $old, $new ) unless $is_transient;
                    return $new;
                }
            }
        }
        else {
            # We are not currently delegating.
            if (@_) {
                # set
                my $old = $self->{ $other_accessor_name };
                my $new = shift;
                if ($old ne $new)
                {
                    $self->{ $other_accessor_name } = $new;
                    $self->signal_change( $other_accessor_name, $old, $new ) unless $is_transient;
                }
                return $new;
            }
            else {
                # get
                return $self->{ $other_accessor_name };
            }
        }
    };
    
    do {
        no strict 'refs';
        no warnings;
        *{$class_name ."::$other_accessor_name"}  = $other_accessor;
    };
    
}

sub mk_dimension_identifying_accessor {
    my ($self, $accessor_name, $ref_class_name, $non_id_properties, $is_transient) = @_;

    # Like mk_rw_accessor, but knows that this accessor is a foreign
    # key to a dimension table, and configures additional accessors.
    # Also makes this accessor "smart", to resolve the dimension
    # id only when needed.

    # Make EAV-like accessors for all of the remote properties
    my $class_name = $self->class_name;

    # Make the actual accessor for the id_by property
    no warnings;    
    my $accessor = sub {
        if (@_ > 1) {
            my $old = $_[0]->{ $accessor_name };
            my $new = $_[1];
            if ($old ne $new)
            {
                $_[0]->{ $accessor_name } = $new;
                $_[0]->signal_change( $accessor_name, $old, $new ) unless $is_transient;
            }
            return $new;
        }
        if (not defined $_[0]->{ $accessor_name }) {
            # Resolve an ID for the current set of values
            # Switch to delegating to that object.
            my %params;
            my $self = $_[0];
            @params{@$non_id_properties} = delete @$self{@$non_id_properties};
            my $delegate = $ref_class_name->get_or_create(%params);
            return undef unless $delegate;
            $_[0]->{ $accessor_name } = $delegate->id;
        }
        return $_[0]->{ $accessor_name };
    };
    
    no strict 'refs';    
    *{$class_name ."::$accessor_name"}  = $accessor;
}

sub mk_class_accessor
{
    no warnings;
    my ($self, $class_name, $accessor_name, $column_name, $variable_name) = @_;
    $variable_name ||= $accessor_name;
    no strict 'refs';
    my $full_accessor_name = $class_name . "::" . $accessor_name;
    my $src =
    "
        sub $full_accessor_name {
            if (\@_ > 1) {
                \$$variable_name = pop;
            }
            return \$$variable_name;
        }
    ";
    print "class accessor: $src\n";
    eval $src;
    if ($@) {
        die "Cannot generate class accessor $accessor_name: $@";
    }
    my $accessor;
    unless ($accessor = $class_name->can($accessor_name)) {
        die "Error generating class accessor $accessor_name.  Not found after eval.";
    }

    if ($column_name)
    {
        *{$class_name ."::" . $column_name}  = $accessor;

        # These are for backward-compatability with old modules.  Remove asap.
        ${$class_name . '::column_for_property'}
            {$accessor_name} = $column_name;

        ${$class_name . '::property_for_column'}
            {$column_name} = $accessor_name;
    }
}


sub mk_object_set_accessors {
    no warnings;
    my ($self, $class_name, $singular_name, $plural_name, $reverse_id_by, $r_class_name) = @_;

    # The accessors may compare undef and an empty
    # string.  For speed, we turn warnings off rather
    # than add extra code to make the warning disappear.
    no warnings;
    no strict 'refs';
    
    # These are set by the resolver closure below, and kept in scope by the other closures
    my $rule_template;
    my @property_names;
    
    my $rule_resolver = sub {
        my ($obj) = @_;        
        $r_class_name->class;
        unless ($reverse_id_by) {
            my @possible_relationships = UR::Object::Reference->get(
                class_name => $r_class_name,
                r_class_name => $class_name
            );
            #print "got " . join(", ", map { $_->id } @possible_relationships) . "\n";
            if (@possible_relationships > 1) {
                die "There are " . scalar(@possible_relationships) 
                    . " from $r_class_name to $class_name.  "
                    . "The definition of $class_name has an ambiguous "
                    . "property $singular_name which must be corrected with a 'reverse_id_by' specification.";
            }
            elsif (@possible_relationships == 0) {
                die "No relationships found between $r_class_name and $class_name.  Error in definition for $class_name $singular_name!"
            }
            $reverse_id_by = $possible_relationships[0]->delegation_name;
        }
        my @property_links = UR::Object::Reference::Property->get(tha_id => $r_class_name . '::' . $reverse_id_by); 
        unless (@property_links) {
            $DB::single = 1;
            Carp::confess("No property links for $r_class_name -> $reverse_id_by?  Cannot build accessor for $singular_name/$plural_name relationship.");
        }
        my %get_params;            
        for my $link (@property_links) {
            my $my_property_name = $link->r_property_name;
            push @property_names, $my_property_name;
            $get_params{$link->property_name}  = $obj->$my_property_name;
        }
        my $tmp_rule = $r_class_name->get_rule_for_params(%get_params);
        $rule_template = $tmp_rule->get_rule_template;        
    };

    my $rule_accessor = sub {
        my $self = shift;
        $rule_resolver->($self) unless ($rule_template);
        return $rule_template->get_rule_for_values(map { $self->$_ } @property_names); 
    };

    my $list_accessor = sub {
        my $self = shift;
        $rule_resolver->($self) unless ($rule_template);
        my $rule = $rule_template->get_rule_for_values(map { $self->$_ } @property_names); 
        
        return $r_class_name->get($rule);
    };
    
    my $arrayref_accessor = sub {
        my $self = shift;
        $rule_resolver->($self) unless ($rule_template);
        my $rule = $rule_template->get_rule_for_values(map { $self->$_ } @property_names); 
        
        return [ $r_class_name->get($rule) ];
    };

    my $iterator_accessor = sub {
        my $self = shift;
        $rule_resolver->($self) unless ($rule_template);
        my $rule = $rule_template->get_rule_for_values(map { $self->$_ } @property_names); 
        
        return UR::Object::Iterator->create_for_filter_rule($rule);
    };

    # These will behave specially if the rule does not specify the ID, or all of the ID.
    my @params_prefix;
    my $params_prefix_resolved = 0;
    my $params_prefix_resolver = sub {
        my @id_property_names = $r_class_name->get_class_object->id_property_names;
        @params_prefix = 
            grep { 
                my $id_property_name = $_;
                ( (grep { $id_property_name eq $_ } @property_names) ? 0 : 1)
            }
            @id_property_names;
        
        # We only do the special single-value spec when there is one property not specified by the rule.
        # This is common for a multi-column primary key where all columns reference a parent object, except an index value, etc.
        @params_prefix = () unless scalar(@params_prefix) == 1;
        $params_prefix_resolved = 1;
    };

    my $single_accessor = sub {
        my $self = shift;
        $rule_resolver->($self) unless ($rule_template);
        my $rule = $rule_template->get_rule_for_values(map { $self->$_ } @property_names);
        $params_prefix_resolver->() unless $params_prefix_resolved;
        unshift @_, @params_prefix if @_ == 1;
        if (@_) {
            return my $obj = $r_class_name->get($rule->params_list,@_);
        }
        else {
            return my $obj = $r_class_name->get($rule);
        }
    };

    my $add_accessor = sub {
        my $self = shift;
        $rule_resolver->($self) unless ($rule_template);
        $params_prefix_resolver->() unless $params_prefix_resolved;
        unshift @_, @params_prefix if @_ == 1;
        my $rule = $rule_template->get_rule_for_values(map { $self->$_ } @property_names);        
        $r_class_name->create($rule->params_list,@_);
    };

    my $remove_accessor = sub {
        my $self = shift;
        $rule_resolver->($self) unless ($rule_template);
        my $rule = $rule_template->get_rule_for_values(map { $self->$_ } @property_names);
        $params_prefix_resolver->() unless $params_prefix_resolved;
        unshift @_, @params_prefix if @_ == 1;        
        my @matches = $r_class_name->get($rule->params_list,@_);
        my $trans = UR::Context::Transaction->begin;
        @matches = map {
            $_->delete or die "Error deleting $r_class_name " . $_->id . " for remove_$singular_name!: " . $_->error_message;
        } @matches;
        $trans->commit;
        return @matches;
    };

    no strict 'refs';
    *{$class_name ."::__$singular_name" . '_rule'}      = $rule_accessor;
    *{$class_name ."::$plural_name"}                    = $list_accessor;
    *{$class_name ."::$singular_name" . '_list'}        = $list_accessor;
    *{$class_name ."::$singular_name" . '_arrayref'}    = $arrayref_accessor;
    *{$class_name ."::$singular_name" . '_iterator'}    = $iterator_accessor;
    *{$class_name ."::$singular_name"}                  = $single_accessor;
    *{$class_name ."::add_$singular_name"}              = $add_accessor;
    *{$class_name ."::remove_$singular_name"}           = $remove_accessor;
}

use Data::Dumper;

sub initialize_direct_accessors {
    my $self = shift;
    my $class_name = $self->{class_name};    
    my $type_name = $self->{type_name};
    
    my %id_property_names;
    for my $property_name (@{ $self->{id_by} }) {
        $id_property_names{$property_name} = 1;
        next if $property_name eq "id";     
    }
    
    my %dimensions_by_fk;
    for my $property_name (sort keys %{ $self->{has} }) {
        my $property_data = $self->{has}{$property_name};
        if ($property_data->{is_dimension}) {
            my $id_by = $property_data->{id_by};
            unless ($id_by) {
                die "No id_by specified for dimension $property_name?";
            }
            if (@$id_by != 1) {
                die "The id_by specified for dimension $property_name must list a single property name!";
            }        
            
            my $dimension_class_name = $property_data->{data_type};
            $dimensions_by_fk{$id_by->[0]} = $dimension_class_name;
             
            my $ref_class_meta = $dimension_class_name->get_class_object;
            my %remote_id_properties = map { $_ => 1 } $ref_class_meta->id_property_names;
            my @non_id_properties = grep { not $remote_id_properties{$_} } $ref_class_meta->all_property_names;        
            for my $expected_delegate_property_name (@non_id_properties) {
                unless ($self->{has}{$expected_delegate_property_name}) {
                    $self->{has}{$expected_delegate_property_name} = {
                        $self->_normalize_property_description(
                            $expected_delegate_property_name,
                            { via => $property_name, to => $expected_delegate_property_name, implied_by => $property_name }
                        )
                    }
                }
            }
        }
    }    
    
    for my $property_name (sort keys %{ $self->{has} }) {
        my $property_data = $self->{has}{$property_name};
        
        my $accessor_name = $property_name;
        my $column_name = $property_data->{column_name};
        my $attribute_name = $property_data->{attribute_name};
        my $is_transient = $property_data->{is_transient};
        
        #my ($props, $cols) = $class_name->_all_properties_columns;
        
        do {
            # Handle the case where the software module has an explicit
            # override for one of the accessors.
            no strict 'refs';
            my $isa = \@{ $class_name . "::ISA" };
            my @old_isa = @$isa;
            @$isa = ();
            if ($class_name->can($property_name)) {
                #warn "property $class_name $property_name exists!";
                $accessor_name = "__$property_name";
            }
            @$isa = @old_isa;
        };
        
        my $accessor_type;
        my @calculation_fields = (qw/calculate calc_perl calc_sql calculate_from/);
        if (my $id_by = $property_data->{id_by}) {
            my $r_class_name = $property_data->{data_type};
            $self->mk_id_based_object_accessor($class_name, $accessor_name, $id_by, $r_class_name);
        }
        elsif (my $via = $property_data->{via}) {
            my $to = $property_data->{to} || $property_data->{property_name};
            if ($property_data->{is_mutable}) {
                $self->mk_indirect_rw_accessor($class_name,$accessor_name,$via,$to,$is_transient);
            }
            else {
                $self->mk_indirect_ro_accessor($class_name,$accessor_name,$via,$to);
            }
        }
        elsif (my $calculate = $property_data->{calculate}) {
            my $calculation_method = $property_data->{calculate};
            my $calculate_from = $property_data->{calculate_from};
            $self->mk_calculation_accessor(
                $class_name,
                $accessor_name,
                $calculation_method,
                $calculate_from
            );
        }
        elsif ($property_data->{is_many} or $property_data->{reverse_id_by}){
            my $reverse_id_by = $property_data->{reverse_id_by};
            my $r_class_name = $property_data->{data_type};
            my $singular_name;
            my $plural_name;
            if ($property_data->{is_many}) {
                require Lingua::EN::Inflect;
                $plural_name = $accessor_name;
                $singular_name = Lingua::EN::Inflect::PL_V($plural_name);
            }
            else {
                $singular_name = $accessor_name;
            }
            $self->mk_object_set_accessors($class_name, $singular_name, $plural_name, $reverse_id_by, $r_class_name);
        }        
        else {        
            if ($self->has_table and not $column_name) {
                # Independent objects are made for these.
                $accessor_type = 'attribute_value';
            }        
            else {
                # Just use key/value pairs in the hash for normal
                # table stuff, and also non-database stuff.
                
                #if ($column_name) {
                #    push @$props, $property_name;
                #    push @$cols, $column_name;
                #}
                
                if ($id_property_names{$property_name} or not $property_data->{is_mutable}) {
                    $accessor_type = 'ro';
                }
                else {
                    $accessor_type = 'rw';
                }
            }
            
            my $maker = "mk_${accessor_type}_accessor";
            $self->$maker($class_name, $accessor_name, $column_name, $property_name,$is_transient);
        }
    }    
    
    # right now we just stomp on the default accessors constructed above where they are:
    # 1. the fk behind a dimensional relationships
    # 2. the indirect properties created for the dimensional relationship
    for my $dimension_id (keys %dimensions_by_fk) {
        my $dimension_class_name = $dimensions_by_fk{$dimension_id};
        my $ref_class_meta = $dimension_class_name->get_class_object;
        my %remote_id_properties = map { $_ => 1 } $ref_class_meta->id_property_names;
        my @non_id_properties = grep { not $remote_id_properties{$_} } $ref_class_meta->all_property_names;        
        for my $added_property_name (@non_id_properties) {
            $self->mk_dimension_delegate_accessors($dimension_id,$dimension_class_name, \@non_id_properties, $added_property_name);
        }
        $self->mk_dimension_identifying_accessor($dimension_id,$dimension_class_name, \@non_id_properties);
    }
    
    return 1;
}


1;
