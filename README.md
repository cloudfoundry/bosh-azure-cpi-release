# Bosh Azure CPI

Cloud Provider Interface (CPI) implementation for Microsft's Azure offering


## Environment Setup

For the time being, BOSH has some limitations regarding CPIs. I have made the necessary fixes and committed them to
a repo located at: 

    git@github.com:nterry/bosh.git
    
Here are the steps to take to get your environment ready (Ideally, if you use RVM or RBENV, create a new gemset):
    
1. Install related tools: 

    >sudo apt-get install -y libsqlite3-dev libxml2-dev libxslt-dev libmysqlclient-dev libpq-dev

2. Clone the BOSH repo mentioned above
3. CD to the bosh_cli folder in the cloned repo and run:

    >gem build bosh_cli.gemspec

    >gem install (outputted_gem_file) --no-ri --no-rdoc
    
4. Repeat the above steps for the bosh_cli_plugin_micro folder in the root of the repo
   

## Installation

Run the following from this repo:

>gem build bosh_azure_cpi.gemspec   
>gem install (outputted_gem_file) --no-ri --no-rdoc
    

## Deployment

1. CD to the bin folder in this repo
2. For the time being, you will need to reserve an IP and place it in the sample_micro_template in the marked place
3. Fill out the fields in the sample_micro_template file
4. Run the following (we will fix the stemcell stuff later):

    >bosh micro deployment sample_micro_template
    
    >bosh download public stemcell (pick one from the list, it doesn't matter, and put its name here)
    
    >bosh micro deploy (downloaded tgz from previous command here)
    
Ultimately, at the time of this writing, you will get to a 'waiting for agent' prompt.... This will never finish as the
'stemcell' that we used is hard-coded to a stock Azure vm image. We will build a stemcell in the future that has the
agent installed to get past this. 


## Contributing

1. Fork it ( https://github.com/[my-github-username]/bosh_azure_cpi/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
