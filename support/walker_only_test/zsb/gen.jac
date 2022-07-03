version:'1.2.1'

node botset { has plan_type, current_bot_count, max_bot_count, current_transaction_count, max_transaction_count, last_reset_date, customer_id, subscription_id, onboarding_flag ;}
node bot { has anchor name, answer_count, description, created_time, last_updated_time, metadata; }
node log_chunk { has history, feedback, callback; }
node category { has anchor name, color; }
node integration { has anchor identifier, path, type, settingsobj; }
node testsuite { has anchor name , test_count, created_time, last_updated_time, last_result_summary, last_ran_time;  }
node testcase { has anchor question , expected_answerid, last_test_status, last_actual_answerid, last_ran_time;  }
node answer {
    has anchor text, show_text, score, created_time, last_updated_time;
    has private encoding; 
    has qlinks, hitcount;
    has editor;
    has categoryid;
    has quick_reply, quick_reply_options;
    has callback;
}
node default_answer { has anchor text,show_text, thresh_score, hitcount; }

walker similar_questions {
    has text, thresh;
    can use.get_embedding, use.dist_score;
    with entry{
        if(not here.thresh): here.thresh=0.1;
        }
    
    log_chunk {
        enc=use.get_embedding(text);
        for i in here.history:
            if(use.dist_score(enc,i[1])<thresh): report i;
    }
}

\/\/botset

walker get_botset {
   
    root { report --> node::botset; }
}

walker change_botset {
   
    root { take --> node::botset; }
    botset{
    if (plan_type): here.plan_type=plan_type;
    if (max_bot_count): here.max_bot_count=max_bot_count;
    if (max_transaction_count):here.max_transaction_count=max_transaction_count;
    if (not here.customer_id)
    {
        if(customer_id):here.customer_id=customer_id;
    }
    if(subscription_id):here.subscription_id=subscription_id;

    }
}

walker set_onboarding_flag {
    has flag;
    root { take --> node::botset; }
    botset{
        if(not here.onboarding_flag): here.onboarding_flag=[];
        here.onboarding_flag = here.onboarding_flag + [flag];
        report here.onboarding_flag;
    }
}

walker reset_onboarding_flag {
    has flag;
    root { take --> node::botset; }
    botset
        {
        here.onboarding_flag = [];
          if(flag){
            for i in here.onboarding_flag
            {
                if(i!=flag)
                {
                    here.onboarding_flag = here.onboarding_flag + [i];
                }
            }
        }
    report here.onboarding_flag;
    }
}

walker reset_botset_count {
root { take --> node::botset; }
 botset{
     here.current_transaction_count=0;
 }
}

\/\/ Bot

walker get_bots {
    has count, bots,bot_count; 
    root { take --> node::botset; }
    botset { 
        bot_count =0;

        for i in --> node::bot{
            bot_count+=1;
            if not(i.answer_count)
            {
            count = spawn i walker :: get_answer_count();
            i.answer_count = count;
            }
          
           report i; 
        }
        here.current_bot_count=bot_count;
        disengage;
        }
}



walker add_bot {
    has name,desc,created_time, default_answer;
    default_answer="I do not have that information yet. Try another query ?";
    thresh_score=0.1;
    metadata={"greetings":[],"defaultAnswer":default_answer,"threshold":thresh_score,"others":{"language":"English (U.S)"}};
    root { 
        take --> node::botset; 
        }
    botset {
        here.current_bot_count+=1;
        if (here.current_bot_count>here.max_bot_count)
        {
            here.current_bot_count-=1;
            disengage;
        }
        created_time=std.time_now();
        bot=spawn here --> node::bot(name=name,description=desc,metadata=metadata,created_time=created_time,last_updated_time=created_time );
        spawn bot walker::create_default_answer(text=default_answer,thresh_score=thresh_score);
        report bot;
        disengage;
    }
   
}

walker delete_bot {
    has botset;
    with entry
    {
        botset=<--node::botset[0];

    }
    bot, category, answer {
        take --> ;
        destroy here;
    }
    with exit{
        botset.current_bot_count-=1;
    }
}

walker change_bot {
    has name,desc,metadata,answer_count,thresh_score,no_response;
    thresh_score=0.1;
    default_answer="I do not have that information yet. Try another query ?";

    bot {
        if (name):here.name=name;
        if (desc):here.description=desc;
        if (metadata)
        {
            if(metadata['defaultAnswer'])
            {
              spawn here walker::change_default_answer(text=metadata['defaultAnswer'],no_report=true);
            }
            else
            {
                if(metadata['threshold']):thresh_score=metadata['threshold'];
                spawn here walker::create_default_answer(text=default_answer,thresh_score=thresh_score);
                metadata['defaultAnswer']=default_answer;
            }
             if(metadata['threshold'])
            {
              spawn here walker::change_default_answer(thresh_score=metadata['threshold'],no_report=true);
            }
            here.metadata=metadata;

        }
        if (answer_count):here.answer_count=answer_count;
        here.last_updated_time=std.time_now();
        if (not no_response):report here;
        disengage;
    }
}

\/\/ Answer 

walker get_answers {
    bot {
        report -->node::answer;
        report -->node::default_answer;
        disengage;
    }
   
}

 walker get_answer_array {
    has anchor answer_array;
    with entry{
        answer_array=[];
    }
    bot {
        for i in -->node::answer
        {
            answer_array = answer_array + [i.text];
        }
    }
 }


walker get_answer_count {
     has anchor count;
     
     with entry{
         count = 0;
     }
    bot {
        for i in -->node::answer{
            count+=1;
        }
    }
 }

walker create_answer {
    has text,show_text,qlinks, categoryid, created_time,answer_count;
    has quick_reply, quick_reply_options, callback,editor;
    can use.enc_answer;
    with entry{
        if (not show_text):show_text = text;
        if (not qlinks):qlinks = [];
        if (not quick_reply):quick_reply = "false";
        if (not quick_reply_options):quick_reply_options = [];
        if (not callback):callback = "false";
        if (not editor):editor = "rte";
        answer_count = spawn here walker::get_answer_count();
    }
    bot  {
        created_time=std.time_now();
        ans = spawn here --> node::answer(text=text,show_text=show_text,qlinks=qlinks,categoryid=categoryid,created_time=created_time,last_updated_time=created_time,quick_reply=quick_reply,quick_reply_options=quick_reply_options,callback=callback,editor=editor);
        pretext="";
        for i in qlinks: pretext+=i;
        ans.encoding = use.enc_answer(pretext+text);
        answer_count+=1;
        report ans;
        disengage;
    }
    with exit{
        spawn here walker:: change_bot(answer_count=answer_count,no_response='true');
    }
}

walker create_many_answers {
    has textlist;

    bot, category  {
       for i in textlist: spawn here walker:: create_answer(text=i,show_text=i);
    }
}

walker delete_answer {

    with entry{
       thisbot=<--node::bot[0];
        answer_count = spawn thisbot walker::get_answer_count();
    }
    answer {
        destroy here;
        answer_count=answer_count-1;
    }
    with exit{
       spawn thisbot walker:: change_bot(answer_count=answer_count,no_response='true');
    }
}

walker change_answer {
    has text,show_text,editor,categoryid, quick_reply, quick_reply_options, callback, qlinks, encoding;
    can use.enc_answer;

    answer {
        if (text)
            {
                pretext="";
                here.text = text;
                if(here.qlinks){for i in here.qlinks: pretext+=i;}
                here.encoding = use.enc_answer(pretext+text);
            }
        if (show_text): here.show_text = show_text;
        if (editor): here.editor = editor;
        if (categoryid): here.categoryid = categoryid;
        if (quick_reply): here.quick_reply = quick_reply;
        if (callback): here.callback = callback;
        if (quick_reply_options): here.quick_reply_options = quick_reply_options;
        here.last_updated_time=std.time_now();
        report here;
        disengage;
    }
}

\/\/ Default Answer 

walker get_default_answer {
    bot {
        report -->node::default_answer;
        disengage;
    }
   
}

walker get_default_answerid {
    has anchor default_answerid;
    bot {
        default_answerid =  --> node::default_answer[0];
        disengage;
    }
}

walker create_default_answer {
    has text, show_text, thresh_score;
    
    bot  {
        if (not thresh_score):thresh_score=0.1;
        take (--> node::default_answer) else {
        default = spawn here --> node::default_answer(text=text,show_text=text,thresh_score=thresh_score);
        }
        disengage;
    }
}


walker change_default_answer {
    has text,show_text,thresh_score,no_report;
    bot{
    take --> node::default_answer[0];
    }
    default_answer {
        if (text)
        {
            here.text = text;
            here.show_text = text;
        }
        if(thresh_score)
        {
            here.thresh_score=thresh_score;
        }
        disengage;
    }
}

walker delete_default_answer {

    default_answer {
        destroy here;
    }
}


\/\/Category 
walker create_category {
    has name, color;
    
    bot  {
        cat = spawn here --> node::category(name=name,color=color);
        report cat;
        disengage;
    }
}

walker get_categories {
    bot {
        report -->node::category;
    }
 }

 walker get_category_array {
     has anchor category_array;

     with entry{
         category_array=[];
     }
     
    bot {
        for i in -->node::category
        {
            category_array+=[{"category":i.name,"id":i}];
        }
    }
 }

 walker get_category_name {
        has anchor category_obj;
        
        category{
            category_obj={"name":here.name, "color":here.color};
        }
    }

 walker change_category {
    has name, color;
    category {
        if (name):here.name=name;
        if (color):here.color=color;
        report here;
        disengage;
    }
 }


walker delete_category {
has thisbot, categoryid, deleteanswers;
    with entry{
       thisbot=<--node::bot[0];
       categoryid=&here;
    }
    category {
       destroy here;
    }
    with exit{
        if (not deleteanswers):deleteanswers="";
       spawn thisbot walker:: reset_category(categoryid=categoryid,deleteanswers=deleteanswers);
        
    }
}

 walker reset_category {
    has categoryid,deleteanswers;
    bot
    {
        for i in node::answer
        {
            if (i.categoryid==categoryid)
            {
                if (deleteanswers=="Yes")
                {
                 destroy i;
                }
                else
                {
                i.categoryid="";
                }
                report i;
            } 
        }
    }
 }


\/\/ Integration 

walker create_integration {
    has identifier, type, path, settings;
    
    bot  {
        intg = spawn here --> node::integration(identifier=identifier,type=type, path=path, settingsobj=settingsobj);
        report intg;
        disengage;
    }
}

 walker get_integrations {
    bot {
        report -->node::integration;
    }
 }


 walker change_integration {
    has identifier, type, path, settingsobj;
    integration {
        if (identifier):here.identifier=identifier;
        if (type):here.type=type;
        if (path):here.path=path;
        if (settingsobj): here.settingsobj=settingsobj;
        report here;
        disengage;
    }
 }




\/\/ Test Suite

walker create_testsuite {
    has name, time;
    
    bot  {
        time=std.time_now();
        suite = spawn here --> node::testsuite(name=name,created_time=time,last_updated_time=time);
        report suite;
        disengage;
    }
}


walker change_testsuite {
    has name;
    
    testsuite  {
        if (name): here.name=name;
        here.last_updated_time=std.time_now();
        report here;
        disengage;
    }
}

walker get_testsuites {
    has count;
    take -->node::testsuite;
    testsuite {
        count = spawn here walker :: get_testcase_count();
            here.test_count = count;
         report here;
        }
}

 walker delete_testsuite {
    testsuite {
        destroy here;
    }
}

walker run_testsuite {
has name;
has response; 
has pass_count, fail_count,actual_answer,thisbot;
has questionarray;

with entry{
    if (not response):response=true;
    thisbot=<--node::bot[0];
    questionarray=[];
    actual_answer="";
    \/\/take -->node::testsuite;
    pass_count=0;
    fail_count=0;
          }

          testsuite{
         
                  for i in --> node::testcase
                    {
                     actual_answer =  spawn thisbot walker::ask_question_nolog_noreport(text=i.question);
                       if (actual_answer == i.expected_answerid) 
                        {

                            pass_count+=1;
                            i.last_test_status= 1;
                            
                        } 
                        else{

                            fail_count+=1;
                            i.last_test_status = 0;
                        }
                    i.last_actual_answerid=actual_answer;
                    i.last_ran_time = std.time_now();
                    }
            here.last_result_summary = {"success": pass_count, "fail": fail_count};
            here.last_ran_time = std.time_now();
            
            if (response==true): report -->node::testcase;
            disengage; 
          }
       
}

\/\/ Test Case 

walker create_testcase {
    has question, answerid, time;
    
    testsuite  {
        time=std.time_now();
        suite = spawn here --> node::testcase(question=question, expected_answerid= answerid, created_time=time,last_updated_time=time);
        report suite;
        disengage;
    }
}

walker create_many_testcases {
    has question_array, answerid, time;
    has current_question_array;
    has answer, default_answerid;

     with entry
    {
        thisbot=<--node::bot[0];
        current_question_array=[];
    }
    
    testsuite  {
        time=std.time_now();
        current_question_array= spawn here walker :: get_testcase_array();

        for i in question_array
        {
                if( not i in current_question_array)
                {
                    current_question_array= current_question_array + [i];
                    if(answer=="default")
                    {
                        default_answerid = spawn thisbot walker :: get_default_answerid();
                        test_case = spawn here --> node::testcase(question=i, expected_answerid= default_answerid, created_time=time,last_updated_time=time);
                        report test_case;
                    }
                    else
                    {
                       answerid =  spawn thisbot walker::ask_question_nolog_noreport(text=i);
                       test_case = spawn here --> node::testcase(question=i, expected_answerid= answerid, created_time=time,last_updated_time=time);
                       report test_case;
                    }
                }
            
        }
        \/\/ report here;
        disengage;
    }
}

walker change_testcase {
    has question, answerid;
    
    testcase  {
        if (question): here.question=question;
        if (answerid): here.expected_answerid=answerid;
        here.last_updated_time=std.time_now();
        report here;
        disengage;
    }
}

walker get_testcases {
    testsuite {
        report -->node::testcase;
    }
 }

 walker get_testcase_array {
    has anchor testcase_array;
    with entry{
        testcase_array=[];
    }
    testsuite {
        for i in -->node::testcase
        {
            testcase_array = testcase_array + [i.question];
        }
    }
 }

 walker get_testcase_count {
     has anchor count;
     
     with entry{
         count = 0;
     }
    testsuite {
        for i in -->node::testcase{
            count+=1;
        }
    }
 }

 walker delete_testcase {
    testcase {
        destroy here;
    }
}

walker run_all_tests {
has name;
has pass_count, fail_count,actual_answer,thisbot;
has questionarray;
has thissuite;
take -->node::testsuite; 
testsuite{
     spawn here walker :: run_testsuite(response='false');
       report here;  
    } 
       
}

\/\/ Import Export 

walker import_answerbank {
    has answerbank;
    has category_array,categoryid;
    has quick_reply,quick_reply_options,callback,editor;
    with entry{

        category_array= spawn here walker :: get_category_array();
        quick_reply='false';
        quick_reply_options = null;
        callback = 'false';
        editor = 'rte';
        current_answer_array=[];

    }

    bot  {
      
       current_answer_array= spawn here walker :: get_answer_array();

       for i in answerbank{

           if( not i['text'] in current_answer_array)
           {
             categoryid="";
             if (i['category'])
             {
           for j in category_array{
               if (i['category']==j['category'])
               {
                   categoryid=j['id'];
               }
              
              }  

               if (not categoryid)
               {
                categoryid = spawn here --> node::category(name=i['category'],color=i['category_color']);
                category_array+=[{"category":i['category'],"id":categoryid}];
               }
             }
             if(quick_reply in i):quick_reply=i['quick_reply'];
             if(quick_reply_options in i):quick_reply_options=i['quick_reply_options'];
             if(callback in i):callback=i['callback'];
             if(editor in i):editor=i['editor'];

           spawn here walker:: create_answer(text=i['text'],show_text=i['show_text'],qlinks=i['qlinks'],categoryid=categoryid,quick_reply=quick_reply,quick_reply_options=quick_reply_options,callback=callback,editor=editor);
       } 
       }
    }
}

walker export_bot{
has name,desc,metadata;
has botobj,ansobj,quickreplyobj;
has category_obj;

with entry {
    botobj = "";
    name= here.name ;
    desc= here.description ;
    metadata = here.metadata;
}

bot  {
    ansobj = [];
    quickreplyobj= [];
   for i in --> node::answer
        {
            categoryid=i.categoryid;
            if(categoryid): category_obj= spawn categoryid walker:: get_category_name();
            else: category_obj={"name":"", "color":""};
            ansobj += [{"text" : i.text,
                        "show_text" : i.show_text,
                        "qlinks" : i.qlinks, 
                        "category": category_obj['name'], 
                        "category_color": category_obj['color'],
                        "quick_reply": i.quick_reply,
                        "quick_reply_options": i.quick_reply_options,
                        "callback": i.callback,
                        "editor": i.editor
                        }];
           
       } 
    }

with exit 
    {
    botobj = {"name": here.name ,"desc": here.description ,"metadata": here.metadata,"answerbank": ansobj };
    report botobj;

    }

}


walker import_bot {
    has name,desc,metadata,answerbank;
    has thisbot;
    has default_answer, thresh_score;
    can use.enc_answer;

    root {
        take --> node::botset;
    }

    botset {
        default_answer="I do not have that information yet. Try another query ?";
        thresh_score=0.1;
        thisbot = spawn here --> node::bot(name=name,description=desc,metadata=metadata,created_time=std.time_now(),last_updated_time=std.time_now());
        report thisbot;
    }

    with exit {
            if(metadata)
            {
                if (metadata['defaultAnswer']):default_answer=metadata['defaultAnswer'];
                if (metadata['threshold']):thresh_score=metadata['threshold'];
            }
            spawn thisbot walker:: create_default_answer(text=default_answer,thresh_score=thresh_score);
            spawn thisbot walker:: import_answerbank(answerbank=answerbank);
     
    }
}

\/\/ Category Templates 

walker get_category_templates{

    has template_array; 

    with entry{
        template_array = 
        [
            {
                "template_category": "Greetings",
                "template_category_color": "#333333",
                "answers": [
                            {
                                "text": "You're welcome! Thanks for chatting with me today.",
                                "show_text": "You're welcome! Thanks for chatting with me today.",
                                "qlinks": []
                            }, {
                                "text": "Thanks for chatting with me today. Goodbye!",
                                "show_text": "Thanks for chatting with me today. Goodbye!",
                                "qlinks": []
                            }, {
                                "text": "I am right where you left me.",
                                "show_text": "<p>I am right where you left me.<\/p>",
                                "qlinks": []
                            }, {
                                "text": "You're so polite!",
                                "show_text": "You're so polite!",
                                "qlinks": []
                            }, {
                                "text": "Good evening!",
                                "show_text": "<p>Good evening! How's your day been?<\/p>",
                                "qlinks": []
                            }, {
                                "text": "Good morning!",
                                "show_text": "<p>Good morning! How are you today?<\/p>",
                                "qlinks": []
                            }, {
                                "text": "Good night. Sleep tight!",
                                "show_text": "<p>Sleep tight!<\/p>",
                                "qlinks": []
                            }, {
                                "text": "Whats up ?  I am just here, waiting to help someone.",
                                "show_text": "<p>I am just here, keen to share my knowledge<\/p>",
                                "qlinks": ["hey what's up"]
                            }, {
                                "text": "I'm doing very well. Thanks!",
                                "show_text": "I'm doing very well. Thanks!",
                                "qlinks": []
                            }
                        ]
	        },
            {
                "template_category": "Emotions",
                "template_category_color": "#599999",
                "answers": [
                            {
                                "text": "Glad you think I'm funny.",
                                "show_text": "Glad you think I'm funny.",
                                "qlinks": []
                            }, {
                                "text": "Wow indeed!",
                                "show_text": "Wow indeed!",
                                "qlinks": []
                            }, {
                                "text": "No big deal. I don't hold a grudge.",
                                "show_text": "No big deal. I don't hold a grudge.",
                                "qlinks": []
                            }, {
                                "text": "Hugs are the best!",
                                "show_text": "Hugs are the best!",
                                "qlinks": []
                            }
                        ]
            }
    ];
    
    }

    with exit
    {
        report template_array;
    }
}


walker import_category_template {
has category_object_array, category_object;
has category_array,categoryid,count;
    
    with entry
    {
        category_array= spawn here walker :: get_category_array();
        count=0;
    }
    
    bot  
    {

        for a in category_object_array
        {
            category_object=category_object_array[count];
            category_name= category_object['template_category'];
            category_color= category_object['template_category_color'];
            count+=1;    
            for i in category_object['answers']
            {
                    categoryid="";
                
                        for j in category_array
                        {
                            if (category_name==j['category'])
                            {
                                categoryid=j['id'];
                            }
                            
                        }  

                        if (not categoryid)
                        {
                            categoryid = spawn here --> node::category(name=category_name,color=category_color); 
                            category_array+=[{"category":category_name,"id":categoryid}];
                            
                        }
                spawn here walker:: create_answer(text=i['text'],show_text=i['show_text'],qlinks=i['qlinks'],categoryid=categoryid,quick_reply=i['quick_reply'],quick_reply_options=i['quick_reply_options'],callback=i['callback'],editor=i['editor']);
            } 
        }
    }
}

\/\/ Ask Question 

walker ask_question {
    has text, selected;
    has max_score, thisbot, botset, dont_log, metadata, default, thresh_score;
    can use.enc_question, use.qa_score;

    with entry {
        enc=use.enc_question(text);
        selected = false;
        max_score=0; 
        thresh_score=0;
        thisbot=here;
        botset=<--node::botset[0];
    }
    bot, default_answer {
        for j in --> node::default_answer: default=j;
        if (default): thresh_score=default.thresh_score;

        for i in --> node::answer{
            score=use.qa_score(enc, i.encoding);
            if(score[0][0]>max_score){
                selected = i;
                max_score=score[0][0];
            }
        }
         selected.score=max_score;

        }
        
    with exit {
        if (max_score>thresh_score){

                if(not dont_log):
                    spawn thisbot walker:: log_question(text=text, selected=selected, metadata=metadata);
                if(selected.hitcount): selected.hitcount+=1;
                else: selected.hitcount=1;
                if ( metadata != {"channel":"ZSB Platform"})
                {
                botset.current_transaction_count+=1;
                }
                report selected;
        }
        else
        {
            if (default)
            {    if(not dont_log):
                    spawn thisbot walker:: log_question(text=text, selected=default, metadata=metadata);
                if(default.hitcount): default.hitcount+=1;
                else: default.hitcount=1;
                report default;
            }
            else : report {"context":{"text":"I do not have that information yet. Try another query ?","show_text":"I do not have that information yet. Try another query ?"}};
            
        }
    }
   
}

walker pub_ask_question:anyone {
    has text, selected;
    has max_score, thisbot, botset, dont_log, metadata, default, thresh_score;
    can use.enc_question, use.qa_score;

    with entry {
        enc=use.enc_question(text);
        selected = false;
        max_score=0; 
        thresh_score=0;
        thisbot=here;
        botset=<--node::botset[0];
    }
    bot, default_answer {
        for j in --> node::default_answer: default=j;
        if (default): thresh_score=default.thresh_score;

        for i in --> node::answer{
            score=use.qa_score(enc, i.encoding);
            if(score[0][0]>max_score){
                selected = i;
                max_score=score[0][0];
            }
        }
         selected.score=max_score;

        }
        
    with exit {
        if (max_score>thresh_score){

                if(not dont_log):
                    spawn thisbot walker:: log_question(text=text, selected=selected, metadata=metadata);
                if(selected.hitcount): selected.hitcount+=1;
                else: selected.hitcount=1;
                if ( metadata != {"channel":"ZSB Platform"})
                {
                botset.current_transaction_count+=1;
                }
                report selected;
        }
        else
        {
            if (default)
            {    if(not dont_log):
                    spawn thisbot walker:: log_question(text=text, selected=default, metadata=metadata);
                if(default.hitcount): default.hitcount+=1;
                else: default.hitcount=1;
                report default;
            }
            else : report {"context":{"text":"I do not have that information yet. Try another query ?","show_text":"I do not have that information yet. Try another query ?"}};
            
        }
    }
   
}


walker ask_question_nolog_noreport {
has text; 
has anchor selected;
can use.enc_question, use.qa_score;

    with entry {
        enc=use.enc_question(text);
        selected = false;
        thresh_score=0;
    }
   bot, default_answer {
        for j in --> node::default_answer: default=j;
        if (default): thresh_score=default.thresh_score;

        max_score = 0;
        for i in --> node::answer{
            score=use.qa_score(enc, i.encoding);
            if(score[0][0]>max_score){
                selected = i;
                max_score=score[0][0];
            }
        }

          if (max_score<thresh_score)
        {
            if (default)
            {   
                selected = default;
            }
            
        }

         
        }
    

}


walker get_question_matches {
    has text, num_matches, matches, thresh_score;
    can use.enc_question, use.qa_score;

    with entry {
        matches=[];
    thresh_score=0;
    }

    bot, default_answer {
       for j in --> node::default_answer: default=j;
       if (default): thresh_score=default.thresh_score; 
    
        enc=use.enc_question(text);
        for i in --> node::answer{
            score=use.qa_score(enc, i.encoding);
            matches += [[score[0][0], &i]];
        }

    }

    with exit {
        if(num_matches>matches.length):
            num_matches=matches.length;
        matches=std.sort_by_col(matches, 0, 'reverse');
        if (matches[0][0]< thresh_score): report [thresh_score,&default];
        for i=0 to i<num_matches by i+=1:
            report matches[i];
    }
}

\/\/Logging 

walker log_question {
    has text, selected, metadata;
    bot {
        take --> node::log_chunk else { 
                spawn here --> node::log_chunk;
                take --> node::log_chunk;
            }            
    }

    log_chunk {
        if(not here.history): here.history=[];
        here.history = [{"datetime":std.time_now(),"log_type":"question","question":text, "answerid":&selected, "answertext":selected.text, "answer_showtext":selected.show_text, "metadata": metadata}] + here.history;
        std.log({"datetime":std.time_now(),"log_type":"question","question":text, "answerid":&selected, "answertext":selected.text, "answer_showtext":selected.show_text, "metadata": metadata});
    }
}

walker log_feedback {
    has feedback, metadata;
    bot {
        take --> node::log_chunk else { 
                spawn here --> node::log_chunk;
                take --> node::log_chunk;
            }
    }

    log_chunk {
        if(not here.feedback): here.feedback=[];
        here.feedback = [{"datetime":std.time_now(),"log_type":"feedback","feedback":feedback, "metadata": metadata}] + here.feedback;
    }
}

walker log_callback {
    has customer_info, session_id;
    bot {
        take --> node::log_chunk else { 
                spawn here --> node::log_chunk;
                take --> node::log_chunk;
            }
    }

    log_chunk {
        if(not here.callback): here.callback=[];
        here.callback = [{"datetime":std.time_now(),"log_type":"callback","customer_info":customer_info, "session_id": session_id}] + here.callback;
    }
}


walker get_log {
    has target_answer;
    bot {
        take --> node::log_chunk;
    }
    log_chunk {
        if(target_answer){
            for i in here.history {
                if(&i['answerid']==target_answer)
                {
                    report i;
                }
            }
        }
        else {report here.history;}
    }
}

walker drain_log {
    bot {
        take --> node::log_chunk;
    }
    log_chunk {
        report here.history;
        here.history=[];
    }
}


\/\/ APi for date filter of log history
walker get_log_date_filter {
    has start_date,end_date;
    with entry
    {
        if not(start_date):start_date=std.time_now();
        if not(end_date):end_date=start_date;
    }
    bot {
        take --> node::log_chunk;
    }
    log_chunk {
            if (not here.history): disengage;
            for i in here.history {
                if(&i['datetime']>=start_date && &i['datetime']<=end_date)
                {
                    std.out(i);
                    report i;
                }
                else 
                {
                    if (&i['datetime']< start_date) : disengage;
                }
            }
           
       
    }
}



walker get_feedback_date_filter {
    has start_date,end_date;
    with entry
    {
        if not(start_date):start_date=std.time_now();
        if not(end_date):end_date=start_date;
    }
    bot {
        take --> node::log_chunk;
    }
    log_chunk {
            if (not here.feedback): disengage;
            for i in here.feedback {
                if(&i['datetime']>=start_date && &i['datetime']<=end_date)
                {
                    report i;
               }
                else 
                {
                     if (&i['datetime']< start_date) 
                    {
                    disengage;
                    }
                }
            }
           
       
    }
}

walker get_callback_date_filter {
    has start_date,end_date;
    with entry
    {
        if not(start_date):start_date=std.time_now();
        if not(end_date):end_date=start_date;
    }
    bot {
        take --> node::log_chunk;
    }
    log_chunk {
            if (not here.callback): disengage;
            for i in here.callback {
                if(&i['datetime']>=start_date && &i['datetime']<=end_date)
                {
                    report i;
               }
                else 
                {
                    if (&i['datetime']< start_date) 
                    {
                    disengage;
                    }
                }
            }
           
       
    }
}

 
walker get_question_log {
    has target_answer;
    bot {
        take --> node::log_chunk;
    }
    log_chunk {
        if(target_answer){
            for i in here.history {
                if(&i['answerid']==target_answer)
                {
                    report [i['question'],i['datetime']];
                }
            }
        }
        else {report here.history;}
    }
}

\/\/ Linking of a question to an answer

walker link_question {
    has text, answerid;
    has thisbot, actual_answer, actual_link_array;
    can use.enc_answer, use.dist_score;
    with entry{
        thisbot=<--node::bot[0];
    }

    answer {
        answerid =  &here;
        actual_link_array = here.qlinks;
        if(here.qlinks){if(not text in here.qlinks): here.qlinks += [text];}
        else: here.qlinks = [text];
        pretext="";
        if(here.qlinks){for i in here.qlinks: pretext+=i;}
        old_enc = here.encoding;
        here.encoding = use.enc_answer(pretext+text);
        actual_answer =  spawn thisbot walker::ask_question_nolog_noreport(text=text);
        if (&actual_answer != answerid ) 
        {
         here.encoding = old_enc;
         here.qlinks = actual_link_array;
         report [[0]]; 
         disengage;
        } 
        else: report use.dist_score(old_enc, here.encoding);
    }
}

walker unlink_question {
    has idx;
    can use.enc_answer, use.dist_score;

    answer {
            if(not here.qlinks or here.qlinks.length < idx): 
            report "Index out of range!";
       else{
            here.qlinks.destroy(idx);
            pretext="";
            for i in here.qlinks: pretext+=i;
            old_enc = here.encoding;
            here.encoding = use.enc_answer(pretext+here.text);
            report use.dist_score(old_enc, here.encoding);
       }
    }
}



\/\/ Init Jac file into Jaseci

walker init {
    root {
        take (--> node::botset)
        else {
            spawn here --> node::botset(plan_type= 'free' , current_bot_count=0, max_bot_count=10, current_transaction_count=0, max_transaction_count=10000, last_reset_date= std.time_now(), onboarding_flag=[] );
            std.log(-->);
            take --> node::botset;
        }
    }
      botset{
            if (not here.plan_type):here.plan_type='free';
            if (not here.max_bot_count):here.max_bot_count=10;
            if (not here.max_transaction_count):here.max_transaction_count=10000;
            if (not here.current_transaction_count):here.current_transaction_count=0;
            if (not here.last_reset_date):here.last_reset_date=std.time_now();
            if (not here.onboarding_flag): here.onboarding_flag=[];
        report here;
        disengage;
        }
}


node data_nugget { has anchor name, data; }
walker create_nugget 
{ has name, data;
 
     spawn here --> node::data_nugget(name=name, data=data); 
    
     }

walker get_nugget {has name; report --> node::data_nugget == name;}
walker delete_nugget {has name; destroy --> node::data_nugget == name;}
walker update_nugget {has name, data; n= --> node::data_nugget == name; if(n): n.data=data;}
