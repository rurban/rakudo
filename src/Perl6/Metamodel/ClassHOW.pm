class Perl6::Metamodel::ClassHOW
    does Perl6::Metamodel::Naming
    does Perl6::Metamodel::Versioning
    does Perl6::Metamodel::Stashing
    does Perl6::Metamodel::AttributeContainer
    does Perl6::Metamodel::MethodContainer
    does Perl6::Metamodel::MultiMethodContainer
    does Perl6::Metamodel::RoleContainer
    does Perl6::Metamodel::MultipleInheritance
    does Perl6::Metamodel::C3MRO
    does Perl6::Metamodel::NonGeneric
    does Perl6::Metamodel::ParrotInterop
{
    has @!does_list;
    has $!composed;
    has @!BUILDPLAN;

    method new_type(:$name = '<anon>', :$repr = 'P6opaque', :$ver, :$auth) {
        my $metaclass := self.new(:name($name), :ver($ver), :auth($auth));
        self.add_stash(pir::repr_type_object_for__PPS($metaclass, $repr));
    }
    
    my @default_parent_type;
    method set_default_parent_type($type) {
        @default_parent_type[0] := $type;
    }

    method compose($obj) {
        # Instantiate all of the roles we have (need to do this since
        # all roles are generic on ::?CLASS) and pass them to the
        # composer.
        my @roles_to_compose := self.roles_to_compose($obj);
        if @roles_to_compose {
            my @ins_roles;
            while @roles_to_compose {
                my $r := @roles_to_compose.pop();
                @ins_roles.push($r.HOW.specialize($r, $obj))
            }
            @!does_list := RoleToClassApplier.apply($obj, @ins_roles)
        }

        # Some things we only do if we weren't already composed once, like
        # building the MRO.
        unless $!composed {
            if self.parents($obj, :local(1)) == 0 && +@default_parent_type && self.name($obj) ne 'Mu' {
                self.add_parent($obj, @default_parent_type[0]);
            }
            self.compute_mro($obj);
            $!composed := 1;
        }

        # Incorporate any new multi candidates (needs MRO built).
        self.incorporate_multi_candidates($obj);

        # Compose attributes.
        for self.attributes($obj, :local) {
            $_.compose($obj);
        }

        # Publish type and method caches.
        self.publish_type_cache($obj);
        self.publish_method_cache($obj);
        
        # Install Parrot v-table mappings.
        self.publish_parrot_vtable_mapping($obj);
		self.publish_parrot_vtable_handler_mapping($obj);
        
        # Create BUILDPLAN.
        self.create_BUILDPLAN($obj);

        $obj
    }
    
    # While we normally end up locating methods through the method cache,
    # this is here as a fallback.
    method find_method($obj, $name) {
        my %methods;
        for self.mro($obj) {
            %methods := $_.HOW.method_table($_);
            if pir::exists(%methods, $name) {
                return %methods{$name}
            }
        }
        my %submethods := $obj.HOW.submethod_table($obj);
        if pir::exists(%submethods, $name) {
            return %submethods{$name}
        }
        pir::null__P();
    }
    
    method publish_type_cache($obj) {
        my @tc;
        for self.mro($obj) {
            @tc.push($_);
            if pir::can($_.HOW, 'does_list') {
                my @does_list := $_.HOW.does_list($_);
                for @does_list {
                    @tc.push($_);
                }
            }
        }
        pir::publish_type_check_cache($obj, @tc)
    }

    method publish_method_cache($obj) {
        # Walk MRO and add methods to cache, unless another method
        # lower in the class hierarchy "shadowed" it.
        my %cache;
        for self.mro($obj) {
            my %methods := $_.HOW.method_table($_);
            for %methods {
                unless %cache{$_.key} {
                    %cache{$_.key} := $_.value;
                }
            }
        }
        
        # Also add submethods.
        my %submethods := $obj.HOW.submethod_table($obj);
        for %submethods {
            %cache{$_.key} := $_.value;
        }
        
        pir::publish_method_cache($obj, %cache)
    }
    
    method does_list($obj) {
        @!does_list
    }
    
    method is_composed($obj) {
        $!composed
    }
    
    method isa($obj, $type) {
        my $decont := pir::nqp_decontainerize__PP($type);
        for self.mro($obj) {
            if $_ =:= $decont { return 1 }
        }
        0
    }
    
    method type_check($obj, $checkee) {
        # The only time we end up in here is if the type check cache was
        # not yet published, which means the class isn't yet fully composed.
        # Just hunt through MRO.
        for self.mro($obj) {
            if $_ =:= $checkee {
                return 1;
            }
            if pir::can($_.HOW, 'does_list') {
                my @does_list := $_.HOW.does_list($_);
                for @does_list {
                    if $_ =:= $checkee {
                        return 1;
                    }
                }
            }
        }
        0
    }
    
    # Creates the plan for building up the object. This works
    # out what we'll need to do up front, so we can just zip
    # through the "todo list" each time we need to make an object.
    # The plan is an array of arrays. The first element of each
    # nested array is an "op" representing the task to perform:
    #   0 code = call specified BUILD method
    #   1 class name attr_name = try to find initialization value
    #   2 class attr_name code = call default value closure if needed
    method create_BUILDPLAN($obj) {
        # Get MRO, then work from least derived to most derived.
        my @plan;
        my @mro := self.mro($obj);
        my $i := +@mro;
        while $i > 0 {
            # Get current class to consider and its attrs.
            $i := $i - 1;
            my $class := @mro[$i];
            my @attrs := $class.HOW.attributes($class, :local(1));
            
            # Does it have its own BUILD?
            my $build := $class.HOW.find_method($class, 'BUILD');
            if $build {
                # We'll call the custom one.
                @plan[+@plan] := [0, $build];
            }
            else {
                # No custom BUILD. Rather than having an actual BUILD
                # in Mu, we produce ops here per attribute that may
                # need initializing.
                for @attrs {
                    if $_.has_accessor {
                        my $attr_name := $_.name;
                        my $name      := pir::substr__SSi($attr_name, 2);
                        @plan[+@plan] := [1, $class, $name, $attr_name];
                    }
                }
            }
            
            # Check if there's any default values to put in place.
            for @attrs {
                my $default := $_.build_closure;
                if $default {
                    @plan[+@plan] := [2, $class, $_.name, $default];
                }
            }
        }
        @!BUILDPLAN := @plan;
    }
    
    method BUILDPLAN($obj) {
        @!BUILDPLAN
    }
}
